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


def runner_nodes(text: str):
    """(job id, key node, value node) for every `jobs.<id>.runs-on`, from the parser.

    The rewrite used to find runners by scanning lines, and each round of
    review found another valid YAML shape the scan misread: a heredoc inside
    `run: |`, an action input, a quoted key, an inline comment, a quoted
    scalar whose continuation line sits at job-key indentation. Only the
    parser knows where a value really starts and ends, so the rewrite edits
    exactly the span it reports and nothing else -- indentation, comments and
    every other line are left byte-for-byte as they were.

    Raises yaml.YAMLError for a document the parser cannot read.
    """
    root = yaml.compose(text, Loader=yaml.SafeLoader)
    if not isinstance(root, yaml.MappingNode):
        return
    for key, value in root.value:
        if not (isinstance(key, yaml.ScalarNode) and key.value == "jobs" and isinstance(value, yaml.MappingNode)):
            continue
        for job_key, job in value.value:
            if not isinstance(job, yaml.MappingNode):
                continue
            for field, runner in job.value:
                if isinstance(field, yaml.ScalarNode) and field.value == "runs-on":
                    yield str(job_key.value), field, runner, bool(job.flow_style)


def rewrite(text: str, target: str) -> tuple[str, int, list[Finding]]:
    """Replace every job's scalar `runs-on` value with `target`."""
    if yaml is None:
        # Without a parser nothing can be located safely, and "nothing
        # reported" would certify jobs that were never looked at -- the same
        # fail-closed rule `check` applies.
        return text, 0, [Finding("cannot convert: PyYAML is unavailable; install it and re-run")]
    try:
        entries = list(runner_nodes(text))
    except yaml.YAMLError as exc:
        problem = str(exc).splitlines()[0] if str(exc) else type(exc).__name__
        return text, 0, [Finding(f"could not be parsed ({problem}); fix the YAML or pin the file")]
    edits: list[tuple[int, int]] = []
    findings: list[Finding] = []
    reported: set[str] = set()
    for job, field, node, flow in entries:
        number = field.start_mark.line + 1
        if isinstance(node, yaml.ScalarNode) and node.value == target:
            # Already converted: nothing is inserted, so none of the reasons a
            # rewrite could be unsafe below apply. Checking this first keeps a
            # repeated run idempotent for a flow-mapping job too.
            continue
        raw = text[node.start_mark.index:node.end_mark.index]
        foreign = (
            not isinstance(node, yaml.ScalarNode)
            # An anchor or tag would be lost with the old value, and an alias
            # reports the anchored node's span, which starts with the anchor.
            or raw.startswith(("&", "!"))
            # A scalar spanning lines, or one inside a flow mapping where the
            # `{`/`}` of the switch expression would end the mapping.
            or node.start_mark.line != node.end_mark.line
            or flow
            # `${{ matrix.os }}` and friends fan a job out; a single label in
            # their place would silently collapse the matrix.
            or (node.value.startswith("${{") and not OWN_EXPRESSION.match(node.value))
        )
        if foreign:
            findings.append(Finding(
                f"line {number}: job {job!r} runs-on {raw} is not a scalar runner this script can rewrite; "
                f"convert it by hand or pin the file"))
            reported.add(job)
            continue
        edits.append((node.start_mark.index, node.end_mark.index))
    updated = text
    for begin, finish in sorted(edits, reverse=True):
        # An empty `runs-on:` is a zero-width span right after the colon, and
        # YAML needs a space between the two.
        lead = " " if begin == finish and not text[begin - 1:begin].isspace() else ""
        updated = updated[:begin] + lead + target + updated[finish:]
    if edits and workflow_unreadable(updated):
        # Never hand back a document the parser cannot read: the caller would
        # write it and, with nothing left to read back, report success.
        return text, 0, [Finding("the rewritten workflow would not parse; nothing was changed. "
                                 "Convert it by hand or pin the file")]
    # Read the result back and name every job still out of step -- anything
    # the walk above cannot reach (a merge key, say) must not pass silently.
    parsed = parsed_job_runners(updated)
    for job, value in sorted((parsed or {}).items(), key=lambda pair: str(pair[0])):
        if value != target and str(job) not in reported:
            findings.append(Finding(
                f"job {job!r}: runs-on is {value!r} in a form this script cannot rewrite; "
                f"convert it by hand or pin the file"))
    return updated, len(edits), findings


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
