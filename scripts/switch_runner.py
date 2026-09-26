#!/usr/bin/env python3
"""Point every workflow's `runs-on` at one switchable runner, and keep it there.

    python3 scripts/switch_runner.py                 # convert to the dynamic form
    python3 scripts/switch_runner.py --mode self-hosted   # hard-pin to the VPS
    python3 scripts/switch_runner.py --mode github        # hard-pin back
    python3 scripts/switch_runner.py --check              # CI drift guard
    python3 scripts/switch_runner.py --fallback self-hosted   # dynamic, VPS when unset

The dynamic form is the point of the exercise:

    runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}

One repository variable then moves every job at once, with no commit and no
workflow edit, and an unset variable reproduces the original `ubuntu-latest`
behavior exactly. The `--mode github` / `--mode self-hosted` forms exist for
anyone who would rather pin the label in git than depend on a variable.

`--check` is why this is a script and not a one-off `sed`: a workflow added
months from now would otherwise quietly hardcode `ubuntu-latest` and keep
burning quota while the switch appeared to be on. A file that genuinely must
pin its runner opts out with a `ci-runner-mode: pinned` comment.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

try:
    import yaml
except ModuleNotFoundError:  # the guard is copied into repositories that may not have it
    yaml = None

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
PIN_MARKER = "ci-runner-mode: pinned"
PIN_LINE = re.compile(r"^#\s*ci-runner-mode:\s*pinned\s*$")
RUNS_ON = re.compile(
    r"""^(?P<indent>\s*)(?P<key>runs-on|"runs-on"|'runs-on')[ \t]*:[ \t]*(?P<value>\S.*?)"""
    r"""(?P<comment>[ \t]+#.*)?[ \t]*$"""
)
JOBS_KEY = re.compile(r"""^(?:jobs|"jobs"|'jobs')[ \t]*:[ \t]*(?:#.*)?$""")

# What `runs-on` resolves to when CI_RUNNER is unset. `ubuntu-latest` is right
# for a repository running on hosted runners today, and wrong for one already
# migrated to the VPS: giving that one a hosted fallback moves every job back
# onto billed minutes the moment the variable lapses -- silently, and in the
# direction that costs money. Such a repository converts with
# `--fallback self-hosted` and keeps its present behaviour while unset.
DEFAULT_FALLBACK = "ubuntu-latest"

# The fallback is interpolated between single quotes inside a GitHub expression,
# so a value carrying a quote would close that string and inject expression
# syntax into every workflow this script writes. Runner labels are a narrow
# vocabulary; anything outside it is refused rather than escaped.
FALLBACK = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

# The one expression this script writes, whatever its fallback. Any other
# `${{ }}` runner -- `${{ matrix.os }}`, a `fromJSON(...)` -- carries intent a
# single label would destroy, so it is reported like a list, not overwritten.
OWN_EXPRESSION = re.compile(r"^\$\{\{ vars\.CI_RUNNER \|\| '[A-Za-z0-9][A-Za-z0-9._-]*' \}\}$")


def dynamic_form(fallback: str = DEFAULT_FALLBACK) -> str:
    """The switchable `runs-on`, resolving to `fallback` when CI_RUNNER is unset."""
    if not FALLBACK.match(fallback):
        raise ValueError(f"invalid fallback {fallback!r}: expected a runner label matching {FALLBACK.pattern}")
    return "${{ vars.CI_RUNNER || '" + fallback + "' }}"


def modes_for(fallback: str = DEFAULT_FALLBACK) -> dict[str, str]:
    """The `--mode` table for one repository's fallback."""
    return {"dynamic": dynamic_form(fallback), "github": "ubuntu-latest", "self-hosted": "self-hosted"}


DYNAMIC = dynamic_form()
MODES = modes_for()


class Finding(str):
    """A `runs-on` this script will not rewrite on its own."""


def workflow_files(directory: pathlib.Path) -> list[pathlib.Path]:
    return sorted(p for p in directory.glob("*.y*ml") if p.suffix in {".yml", ".yaml"})


def is_pinned(text: str) -> bool:
    """True only when the marker appears as a top-level YAML comment.

    A bare substring test exempted the whole file on any occurrence, so a step
    that merely printed or grepped the marker -- inside `run:`, an input, any
    string -- switched the guard off for that workflow and let it keep a
    hardcoded runner. The documented opt-out is a comment at column zero, so
    that is what this matches.
    """
    return any(PIN_LINE.match(line) for line in text.splitlines())


def job_runner_lines(lines: list[str]) -> dict[int, str]:
    """Line indexes holding a job's own `runs-on`, mapped to that job's id.

    Only `jobs.<id>.runs-on` is a runner. Matching every indented `runs-on:`
    line also rewrote text that merely looks like one -- a line inside a
    `run: |` heredoc, an action input, generated YAML -- silently changing a
    command while reporting it as a converted runner. So the line must sit
    directly under a job, at that job's own key indentation. A block scalar's
    content is always indented deeper than the key that owns it, so it can
    never land at that column.
    """
    marked: dict[int, str] = {}
    in_jobs = False
    job_indent: int | None = None
    child_indent: int | None = None
    job: str | None = None
    for index, raw in enumerate(lines):
        line = raw.rstrip("\r\n")
        stripped = line.lstrip(" ")
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(stripped)
        if indent == 0:
            in_jobs = bool(JOBS_KEY.match(line))
            job_indent = child_indent = None
            job = None
            continue
        if not in_jobs:
            continue
        if job_indent is None:
            job_indent = indent
        if indent <= job_indent:
            job = stripped.split(":", 1)[0].strip().strip("\"'")
            child_indent = None
            continue
        if child_indent is None:
            child_indent = indent
        if indent == child_indent and job is not None and RUNS_ON.match(line):
            marked[index] = job
    return marked


def rewrite(text: str, target: str) -> tuple[str, int, list[Finding]]:
    """Replace every job's scalar `runs-on:` value with `target`."""
    lines = text.splitlines(keepends=True)
    runners = job_runner_lines(lines)
    out: list[str] = []
    changed = 0
    findings: list[Finding] = []
    reported: set[str] = set()
    for index, line in enumerate(lines):
        match = RUNS_ON.match(line.rstrip("\r\n")) if index in runners else None
        if not match:
            out.append(line)
            continue
        number = index + 1
        value = match.group("value")
        if value.startswith(("[", "{", "&", "*")) or (value.startswith("${{") and not OWN_EXPRESSION.match(value)):
            # A sequence or anchor carries labels this script cannot merge into a
            # single one without inventing intent. Mangling it silently would be
            # worse than saying so.
            findings.append(Finding(f"line {number}: {value} is not a scalar runner; convert it by hand or pin the file"))
            reported.add(runners[index])
            out.append(line)
            continue
        if value == target:
            out.append(line)
            continue
        newline = line[len(line.rstrip("\r\n")):]
        comment = match.group("comment") or ""
        out.append(f"{match.group('indent')}{match.group('key')}: {target}{comment}{newline}")
        changed += 1
    updated = "".join(out)
    # The line scan sees only the block spellings it can safely edit. A job
    # written as a flow mapping, or whose key the scan cannot place, used to be
    # skipped with zero updates and a clean exit -- after which `--check`
    # rejected the unchanged job and told the operator to run this very
    # command. Read the result back and name every job still out of step.
    if yaml is None:
        # Without a parser the read-back cannot run, and "nothing reported" would
        # certify a flow-mapping job the line scan never saw -- the same
        # fail-closed rule `check` applies.
        findings.append(Finding("cannot verify every job was converted: PyYAML is unavailable; "
                                "install it and re-run, or check the result with --check"))
        return updated, changed, findings
    parsed = parsed_job_runners(updated)
    for job, value in sorted((parsed or {}).items(), key=lambda pair: str(pair[0])):
        if value != target and str(job) not in reported:
            findings.append(Finding(
                f"job {job!r}: runs-on is {value!r} in a form this script cannot rewrite; "
                f"convert it by hand or pin the file"))
    return updated, changed, findings


def runs_on_required(text: str) -> bool:
    """False when every job delegates to a reusable workflow, which takes no runner.

    `jobs.<id>.uses` is a normal workflow shape with no `runs-on` to switch, and
    the only way to satisfy a blanket requirement would be a pin marker that
    says something untrue about it.
    """
    if yaml is None:
        # This guard is copied into other repositories and runs on whatever
        # runner they use, where PyYAML may be absent and `pip install` may be
        # refused outright (PEP 668). Losing the parser must not let a file
        # through unchecked, so the exemption simply cannot be proved and a
        # runner is demanded -- the operator sees a reported file they can pin,
        # rather than a workflow with no runner passing silently.
        return True
    try:
        spec = yaml.safe_load(text)
    except yaml.YAMLError:
        # Unparseable is not a licence to skip the check; demand a runner and
        # let the operator see the real problem.
        return True
    # `spec or {}` only covers a falsy root. A valid YAML document whose top
    # level is a list, string or number loads fine and has no `.get`, which
    # would crash the guard instead of reporting the malformed workflow -- the
    # same isinstance check already applied one line down.
    if not isinstance(spec, dict):
        return True
    jobs = spec.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return True
    # Exempt only a workflow whose every job really is a reusable-workflow
    # caller. `any(... "uses" not in job ...)` said false for `jobs: {}` and for
    # `jobs: {build: null}`, letting a workflow with no runner at all through
    # the guard -- the opposite of how the malformed-root case is treated.
    return not all(isinstance(job, dict) and "uses" in job for job in jobs.values())


def _load_workflow(text: str):
    """`yaml.safe_load` with job ids kept as written and duplicates refused.

    PyYAML implements YAML 1.1, which resolves unquoted `on`, `off`, `yes`,
    `no`, `true` and `false` to booleans -- including as MAPPING KEYS. GitHub
    accepts all of them as job ids, so `jobs:` holding both `on:` and `yes:` is
    two jobs in the file and ONE key in the loaded dict: the second overwrites
    the first, and a hardcoded runner in the first disappears before this script
    can see it. Reproduced before this loader existed; the guard reported a
    clean file.

    Keys therefore come from the scalar node's own text, and a collision is
    raised rather than silently resolved -- two jobs GitHub can tell apart must
    not become one here.
    """
    class Loader(yaml.SafeLoader):
        pass

    def mapping(loader_self, node, deep=False):
        out = {}
        for key_node, value_node in node.value:
            key = (key_node.value if isinstance(key_node, yaml.ScalarNode)
                   else loader_self.construct_object(key_node, deep=deep))
            if key in out:
                raise yaml.YAMLError(f"duplicate key {key!r}")
            out[key] = loader_self.construct_object(value_node, deep=deep)
        return out

    Loader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    return yaml.load(text, Loader=Loader)


def parsed_job_runners(text: str) -> dict | None:
    """Each non-caller job's `runs-on` as the parser sees it, or None if unreadable.

    The line scan cannot be the whole guard. `runs-on:` is one of several
    spellings YAML accepts for the same key -- `"runs-on":` and a flow mapping
    are equally valid and the regex matches neither -- while a file needs only
    ONE recognized line to set `found`, after which the structural check is
    skipped entirely. A second job spelled any other way then keeps its
    hardcoded runner with the guard reporting success, which is precisely the
    drift this script exists to catch. Reading the parsed document instead sees
    every job however it is spelled.

    None means the document could not be read -- no parser, invalid YAML, or a
    shape with no `jobs` mapping -- and the caller falls back to the line scan
    rather than treating "unreadable" as "clean".
    """
    if yaml is None:
        return None
    try:
        spec = _load_workflow(text)
    except yaml.YAMLError:
        return None
    if not isinstance(spec, dict):
        return None
    jobs = spec.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return None
    # A reusable-workflow caller has no runner to switch; everything else does,
    # including a job whose `runs-on` is missing entirely (value None).
    return {name: (job.get("runs-on") if isinstance(job, dict) else None)
            for name, job in jobs.items()
            if not (isinstance(job, dict) and "uses" in job)}


def workflow_unreadable(text: str) -> bool:
    """True when the document cannot be read at all, as opposed to holding no jobs.

    `parsed_job_runners` returns None for both, and the difference decides
    whether the line scan may be trusted. A document that raises, or loads as
    something other than a mapping, says nothing about what is inside it -- the
    scan would still set `found` on one recognized line and certify the file. A
    document that parses cleanly and simply has no `jobs` is a readable
    statement, and the existing `runs_on_required` path already handles it.
    """
    if yaml is None:
        return True
    try:
        spec = _load_workflow(text)
    except yaml.YAMLError:
        return True
    return not isinstance(spec, dict)


def check(directory: pathlib.Path, expected: str = DYNAMIC) -> list[str]:
    """Report every workflow whose runner is not the expected form."""
    problems: list[str] = []
    if yaml is None:
        # Failing closed, because the alternative is worse than failing. The
        # line scan below cannot see a job written `"runs-on":` or as a flow
        # mapping, and one recognized line used to vouch for a whole file -- so
        # falling back to it reports success on exactly the drift the parsed
        # reading was added to catch. A guard that cannot check must say so.
        return ["cannot verify runners: PyYAML is unavailable, and the line scan alone "
                "cannot see every job shape. Install PyYAML for this step -- see docs/ci-runner-mode.md."]
    for path in workflow_files(directory):
        text = path.read_text(encoding="utf-8")
        name = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        if is_pinned(text):
            continue
        runners = parsed_job_runners(text)
        if runners is None and workflow_unreadable(text):
            # Same rule as the missing-parser case above, for the same reason.
            # Round two closed that one and left this one open: a file whose
            # YAML raises still fell through to the line scan, and one
            # recognized `runs-on:` line carrying the expected value set `found`
            # and returned no problems -- reporting the tree clean while a
            # second hardcoded job sat unread in the same file. Nothing here has
            # been checked, so the guard says so instead of certifying it.
            problems.append(
                f"{name}: could not be parsed, so its runners cannot be verified. "
                f"Fix the YAML, or add a '{PIN_MARKER}' comment if this one must pin."
            )
            continue
        if runners is not None:
            # Authoritative when the document can be read: every job, whatever
            # spelling it used. The line scan below is the fallback for a file
            # this cannot parse, not a second opinion on one it can.
            for job, value in sorted(runners.items(), key=lambda pair: str(pair[0])):
                if value != expected:
                    problems.append(
                        f"{name}: job {job!r} runs-on is {value!r}, expected {expected!r}. "
                        f"Run scripts/switch_runner.py, or add a '{PIN_MARKER}' comment if this one must pin."
                    )
            continue
        found = False
        for number, line in enumerate(text.splitlines(), start=1):
            match = RUNS_ON.match(line)
            if not match:
                continue
            found = True
            value = match.group("value")
            if value != expected:
                problems.append(
                    f"{name}:{number}: runs-on is {value!r}, expected {expected!r}. "
                    f"Run scripts/switch_runner.py, or add a '{PIN_MARKER}' comment if this one must pin."
                )
        if not found and runs_on_required(text):
            problems.append(f"{name}: no runs-on found; a workflow with no switchable runner cannot follow the switch")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", default="dynamic", choices=sorted(MODES))
    parser.add_argument("--check", action="store_true", help="verify only; do not write")
    parser.add_argument("--dry-run", action="store_true", help="report what would change")
    parser.add_argument("--workflow-dir", type=pathlib.Path, default=WORKFLOW_DIR)
    parser.add_argument(
        "--fallback",
        default=DEFAULT_FALLBACK,
        help="runner used when CI_RUNNER is unset (default: %(default)s); pass "
             "self-hosted for a repository already running on the VPS, so an "
             "unset variable keeps it there instead of returning it to billed minutes",
    )
    args = parser.parse_args(argv)

    directory = args.workflow_dir
    if not directory.is_dir():
        print(f"no workflow directory at {directory}", file=sys.stderr)
        return 1

    try:
        targets = modes_for(args.fallback)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1

    if args.check:
        # --mode is what the tree is expected to look like, so a repository that
        # hard-pinned with `--mode self-hosted` checks with the same flag rather
        # than failing against a form it deliberately does not use.
        problems = check(directory, targets[args.mode])
        for problem in problems:
            print(problem, file=sys.stderr)
        if problems:
            print(f"\n{len(problems)} workflow runner(s) out of step.", file=sys.stderr)
            return 1
        print(f"every workflow runner matches mode={args.mode}.")
        return 0

    target = targets[args.mode]
    total = 0
    findings: list[str] = []
    for path in workflow_files(directory):
        text = path.read_text(encoding="utf-8")
        name = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        if is_pinned(text):
            print(f"{name}: pinned, left alone")
            continue
        updated, changed, file_findings = rewrite(text, target)
        findings.extend(f"{name}: {f}" for f in file_findings)
        if changed and not args.dry_run:
            path.write_text(updated, encoding="utf-8")
        if changed:
            verb = "would set" if args.dry_run else "set"
            print(f"{name}: {verb} {changed} runs-on -> {target}")
            total += changed
    for finding in findings:
        print(finding, file=sys.stderr)
    print(f"{total} runner(s) {'would be ' if args.dry_run else ''}updated to mode={args.mode}.")
    # Every convertible runner is still written, but a run that left any job
    # out of step says so in its exit code: reporting "0 updated" and exiting
    # 0 read as success to anyone scripting this, while `--check` failed on
    # the very jobs left behind.
    if findings:
        print(f"{len(findings)} runner(s) left unconverted; see above.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
