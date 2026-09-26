> **Ported** from `vohoailinh90/claude-agent-routing-template`, which owns
> `pick_runner.py` and `switch_runner.py` and holds their tests and mutation
> manifests. Fix a bug there and re-port; do not diverge here.
>
> Fleet-level tooling — `sync_ci_runner.py`, which keeps `CI_RUNNER` in step
> across every repository from one quota reading, and `setup-vps-runner.sh`,
> which registers the runners — lives in that repository and runs from the
> VPS, not from here.
>
> **`pick_runner.py` and `runner-mode.yml` are deliberately not ported into
> this repository.** The in-Actions probe needs an isolated runner of its own
> holding a PAT, and a personal account cannot afford one such runner per
> repository — `sync_ci_runner.py` on the VPS is the supported way to drive
> `CI_RUNNER` here. **Sections below describing the in-Actions probe,
> including the dispatchable reset in *Getting unstuck*, do not exist here.**

# CI runner mode — GitHub-hosted or the VPS

GitHub-hosted minutes are billed for private repositories, and this repository
is private. When the allowance runs out, workflow runs stop starting. A
self-hosted runner has no per-minute billing, so the work can keep moving on a
VPS until the allowance resets — and move back afterwards.

This is that switch. Nothing here is on by default: with no variables set, every
workflow runs on `ubuntu-latest` exactly as before.

## The switch

Every job resolves its runner from one repository variable:

```yaml
runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}
```

Setting `CI_RUNNER` moves **every job in the repository** at once, with no commit
and no workflow edit. Unsetting it restores the default.

```bash
gh variable set CI_RUNNER --body self-hosted     # move everything to the VPS
gh variable set CI_RUNNER --body ubuntu-latest   # move everything back
gh variable delete CI_RUNNER                     # back to the built-in default
```

If you would rather pin the label in git than depend on a variable:

```bash
python3 scripts/switch_runner.py --mode self-hosted   # rewrite every workflow
python3 scripts/switch_runner.py --mode github        # rewrite them back
python3 scripts/switch_runner.py                      # restore the dynamic form
python3 scripts/switch_runner.py --dry-run            # preview, write nothing
```

A workflow that genuinely must pin its own runner opts out with a
`# ci-runner-mode: pinned` comment; `runner-mode.yml` does exactly that.

If you hard-pin the whole tree, tell the drift guard so: `--check` verifies the
tree matches `--mode`, which defaults to the dynamic form. A repository pinned
with `--mode self-hosted` checks with `--mode self-hosted` too, and the workflow
step that runs the guard has to be updated to match. **In this repository that
step is the last one in `.github/workflows/runner-drift-guard.yml`**, which
today runs `switch_runner.py --check --fallback ubuntu-latest`; the template
this is ported from runs it from `python-app.yml` instead, which is a file this
repository does not carry. Rewriting the labels without updating that
invocation leaves the guard checking against a form you deliberately chose not
to use, and the next run fails.

## Automatic mode

`.github/workflows/runner-mode.yml` runs every six hours **on the VPS**, reads
the Actions billing API, and sets `CI_RUNNER` for you.

It runs on the VPS deliberately. It is the one job that has to work when the
hosted quota is gone, and self-hosted minutes are not billed. Nothing else gains
a dependency on it: other workflows read the variable, they do not wait for the
probe.

It runs on a **separate runner** from everything else, and that is not optional —
see *Why the probe needs its own runner* below. It is also opt-in: with
`CI_PROBE_LABEL` unset there is no probe job at all. If the VPS is down while `CI_RUNNER` still says `ubuntu-latest`, the variable
simply stops being updated and jobs keep using that value — a stale decision,
not a stalled queue. The reverse case is worse, and worth knowing before you
rely on this: see *Getting unstuck* below.

### Setup

1. **Register the VPS runner** under Settings → Actions → Runners. Note the
   label it registers with (`self-hosted` by default). This is the runner your
   ordinary jobs will use.
2. **Give your ordinary VPS runner a custom label** — say `vps` — and set
   `CI_SELF_HOSTED_LABEL` to it. Do **not** leave it at the default
   `self-hosted`: GitHub gives *every* self-hosted runner that label, so
   `runs-on: self-hosted` reaches the probe runner too, and the isolation below
   would be defeated before it started.
3. **Register a second runner for the probe**, with its own label — say
   `probe-runner` — and set `CI_PROBE_LABEL` to it. It must be a runner that
   never executes repository code; the reason is below. Put it on a separate
   machine: a second runner process on the same box shares `/proc` and defeats
   the point.
4. **Create a token** and store it as the repository secret `CI_RUNNER_TOKEN`.
   The built-in `GITHUB_TOKEN` can read neither billing nor write variables, so
   this step is not optional for auto mode. Use a **fine-grained** PAT with only:
   - Repository permissions → **Variables: Read and write**
   - Account permissions → **Plan: Read-only** (billing lives on the account,
     not the repository)

   A classic PAT also works, but `repo` plus `user` is far more authority than
   this needs, and it is the difference between a leaked token costing you a
   repository variable and costing you every repository you can push to. Prefer
   the fine-grained one.
6. **Set the variables you want to change** (all optional):

   | Variable | Default | Meaning |
   |---|---|---|
   | `CI_PROBE_LABEL` | unset → no probe | the probe runner's label; auto mode is off until set |
   | `CI_RUNNER_MODE` | `auto` | `auto`, `github` or `self-hosted` |
   | `CI_RUNNER` | unset → `ubuntu-latest` | the live label; auto mode writes this |
   | `CI_SELF_HOSTED_LABEL` | `self-hosted` | what auto mode writes when quota is low |
   | `CI_GITHUB_LABEL` | `ubuntu-latest` | what it writes when quota is healthy |
   | `CI_LOW_WATER` | `50` | switch to the VPS at or below this many minutes |
   | `CI_HIGH_WATER` | `200` | switch back at or above this many minutes |
   | `CI_INCLUDED_MINUTES` | unset | your plan's monthly allowance (see below) |

5. **Try it now** rather than waiting for the schedule:

   ```bash
   gh workflow run runner-mode.yml -f mode=auto
   ```

   The run summary shows the decision and the reason for it.

`CI_RUNNER_MODE` set to `github` or `self-hosted` pins the answer and ignores
billing entirely — useful when you already know which side you want and do not
care what the API says.

### Why two thresholds

A single threshold makes the variable flap: a remainder hovering on the mark
rewrites `CI_RUNNER` on every probe, and jobs land on a different runner each
time. Between the low and high marks the standing choice is kept, so it takes a
real move in either direction to switch.

### When quota cannot be read

Two things vary and neither is knowable in advance — the owner may be a user or
an organization, and the account may be on the legacy or the enhanced billing
platform — so the probe tries four candidates in order and takes the first that
answers `200`:

```text
/users/{owner}/settings/billing/actions                        legacy, user
/orgs/{owner}/settings/billing/actions                         legacy, org
/users/{owner}/settings/billing/usage?year=&month=             enhanced, user
/organizations/{owner}/settings/billing/usage?year=&month=     enhanced, org
```

They are four explicit URLs rather than a grid of path segments, because the
enhanced platform does not mirror the legacy paths: its organization report
lives under `/organizations/`, not `/orgs/`, and both enhanced reports take an
explicit year and month. The window is not optional in practice — the allowance
is monthly, so a year-wide report would overstate minutes used, clamp the
remainder to zero and pin every job to the VPS permanently. Failing to decide is
safe; deciding the wrong way is not.

The legacy endpoints report usage *and* the allowance, so nothing needs
configuring. The enhanced ones report consumption but **not** your plan's
allowance — set `CI_INCLUDED_MINUTES` to supply it, or the probe has no
remainder to compute and reports undetermined.

The enhanced report also separates usage by runner SKU and states **native**
minutes, which is not what the allowance counts. On a private repository one
native minute costs:

| Runner | Included minutes per native minute |
|---|---:|
| Linux | 1 |
| Windows | 2 |
| macOS | 10 |

So the probe converts before subtracting. A SKU it does not recognize — a
larger runner, say, which is billed per minute and draws on the allowance not
at all — is **not** treated as 1x: the whole report is reported undetermined
and `CI_RUNNER` is left alone. Counting it at 1x would be wrong in both
directions, and the overstating direction is the dangerous one, since it keeps
jobs on a hosted runner whose quota is already spent — the failure this switch
exists to prevent.

A wrong candidate fails harmlessly; the run log shows what each one returned.

If the response carries a `Link` header offering a next page, the probe reports
the report as incomplete and decides nothing. One page of a paginated report is
not the report: a first page holding no Actions items would otherwise read as
zero usage and move jobs onto an allowance that may already be spent.

If neither shape parses, or the token is missing, or the API errors, the probe
leaves `CI_RUNNER` untouched and says so in the run summary. It never guesses:
a wrong guess moves every job in the repository onto a runner that may not
exist.

## Several repositories on one account

Everything above switches one repository from inside Actions. A personal
account with several private repositories hits two walls.

**There is no user-level self-hosted runner.** GitHub shares runners at the
organization level, and a personal account has no organization, so a runner is
registered per repository. `scripts/setup-vps-runner.sh` does that in a loop —
one downloaded package, one runner directory and one service per repository:

```bash
CI_RUNNER_TOKEN=<pat> ./scripts/setup-vps-runner.sh \
    --owner OWNER --repo A --repo B --repo C
```

**And the probe does not divide.** `runner-mode.yml` needs a runner that never
executes repository code, so auto mode across N repositories would mean N more
persistent runner processes, each holding a PAT — the very exposure the
isolation rule exists to prevent, multiplied.

`scripts/sync_ci_runner.py` is the same decision taken once, outside Actions:

```bash
CI_RUNNER_TOKEN=<pat> python3 scripts/sync_ci_runner.py \
    --owner OWNER --repo A --repo B --included-minutes 2000
```

One cron entry on the VPS covers every repository. No probe runner exists to be
shared with untrusted code, and the PAT never travels to a runner at all. The
decision is not reimplemented — it imports `pick_runner.decide` unchanged, so
the hysteresis, the SKU conversion and the refusal to guess behave exactly as
they do in the workflow, and `SyncTests` pins its billing endpoints to the
probe's so the two cannot drift apart.

Per-repository auto mode via `CI_PROBE_LABEL` still works and is untouched. Use
it for a repository that must decide for itself; use the sync for a fleet.

### Which OS user holds the PAT

`sync_ci_runner.py` and `setup-vps-runner.sh` both read `CI_RUNNER_TOKEN` from
the environment rather than a flag, which keeps it out of `ps`. That is not the
whole problem. `/proc/<pid>/environ` is readable by any process sharing the
reading process's UID, and a self-hosted runner is persistent: a process an
earlier job left behind runs as the runner account and outlives the job that
started it. Run either script under the runner's own account and that leftover
can read the PAT straight out of the environment for as long as the script runs.

So give the token its own unprivileged user — one the runner account cannot
reach — and cron the sync there. The runner account never needs the PAT: it
needs a registration token, which is single-purpose and expires in an hour.

That advice is about the **sync**, and following it for setup would defeat it.
`setup-vps-runner.sh` installs each service as an account you name, and by
default that account is whoever ran the script — so running setup as the
dedicated token user would make the token user the runner account, which is
exactly the pairing this section exists to break. Run setup from the control
account and name the runner account explicitly:

```bash
CI_RUNNER_TOKEN=<pat> ./scripts/setup-vps-runner.sh \
    --owner OWNER --repo A --repo B --runner-user ci-runner
```

This is the same reasoning that gives the in-Actions probe its own runner, one
layer down: the question is never only what a credential is passed as, but which
identities can read it once it exists.

## Repositories already on the VPS

A repository that has *already* migrated to `runs-on: self-hosted` must not be
converted with the default fallback. `${{ vars.CI_RUNNER || 'ubuntu-latest' }}`
sends every job back to billed minutes the moment `CI_RUNNER` is unset — which
is its initial state — and it does so silently, in the direction that costs
money. Convert it with the fallback it actually wants:

```bash
python3 scripts/switch_runner.py --fallback self-hosted
python3 scripts/switch_runner.py --check --fallback self-hosted   # and the guard to match
```

The drift guard has to be told the same value, so the repository's
`runner-drift-guard` workflow passes `--fallback` too. A fallback is
interpolated between single quotes inside a GitHub expression, so it is
validated against a runner-label pattern and refused rather than escaped if it
could close that string.

## Getting unstuck

There is one state this design cannot recover from on its own, and it is worth
understanding because it is the mirror image of the problem it solves.

If `CI_RUNNER` says `self-hosted` and that runner goes offline, every ordinary
job is stuck. Whether anything can fix it from inside Actions depends on where
the probe lives:

- **Probe on its own machine, still up** — `decide` runs, sees the quota, and
  can write `CI_RUNNER` back. This is one more reason the probe's separate
  runner is worth its keep, beyond the token isolation it exists for.
- **Probe on the same machine, or also down** — nothing inside Actions can
  reach the variable. `decide` cannot run, and the one workflow that could
  reset it needs a runner that is gone.

Two ways out, in order of preference:

1. **From your machine**, which always works — no runner and no quota needed:

   ```bash
   gh variable set CI_RUNNER --body ubuntu-latest
   ```

2. ~~**From the Actions tab**, dispatch `runner-mode.yml` with **reset**
   ticked.~~ **Not available in this repository** — `runner-mode.yml` is not
   ported here (see the note at the top), so there is no reset workflow to
   dispatch. Option 1 is the only route, and it costs this repository little:
   its fallback is `ubuntu-latest`, so an unset variable can never strand it
   on a VPS that is down.

   For reference, in a repository that does carry the probe, that option
   dispatches `runner-mode.yml` with **reset** ticked. That job is deliberately pinned to
   `ubuntu-latest` — the opposite of every other job here — precisely so it does
   not depend on the runner that is missing, and it sits outside the probe's
   concurrency group so a scheduled probe stuck waiting for the offline runner
   cannot hold it in the queue behind itself. It costs hosted minutes, but only
   when a human asks for it.

If the VPS is down *and* hosted quota is exhausted, only option 1 exists. That
is not a flaw in the switch: with no runner of either kind available there is
nothing for CI to run on, whatever the variable says.

## Why the probe needs its own runner

A self-hosted runner is persistent. It is not destroyed between jobs, and the
jobs on it run as the same user, so a process one job leaves behind can read a
later job's environment out of `/proc`.

The probe holds `CI_RUNNER_TOKEN`. An ordinary CI workflow — `ci.yml` here,
`python-app.yml` in the template — runs on `pull_request` and installs from
`requirements*.txt` before running the tests: code written by the pull request,
plus whatever PyPI serves for its dependencies. Put those two on the
same runner and pull-request code can harvest a long-lived PAT it would
otherwise never see, escalating from the ephemeral read-scoped `GITHUB_TOKEN`
that a PR job is supposed to get.

That is not only a story about a malicious collaborator. A compromised package
in your dependency tree runs with exactly the same access during `pip install`,
and it never had to log into anything.

So the probe takes its own label, has no default, and the job fails before
anything touches the token if that label is not isolated.

**A label does not identify a machine**, which is the part that took several
review rounds to get right. GitHub gives every self-hosted runner `self-hosted`
plus its OS and architecture, on top of whatever custom label it registered
with. So a probe registered as `probe-runner` still answers `runs-on:
self-hosted`, and comparing the two strings would find no collision where there
plainly is one.

The check therefore rejects four things: a probe label that is blank once
whitespace is collapsed, a probe label that is one of those auto-assigned
labels, any of `CI_RUNNER` / `CI_SELF_HOSTED_LABEL` / `CI_GITHUB_LABEL` being
one of them, and any of them resolving to the probe's own label. It lives in
`scripts/pick_runner.py` rather than in the workflow's shell, so it normalizes
labels exactly as the picker does — case-folded past ASCII, whitespace collapsed
the way the emitted value will be — and reads the same defaults. Three
consecutive review rounds found that guard wrong in the same shape, each time
because a shell copy compared something slightly different from what the picker
would actually write.

**Only the probe's own platform collides.** A runner carries `self-hosted` plus
one OS label and one architecture label — not the whole vocabulary. The job
passes its own `RUNNER_OS` and `RUNNER_ARCH` to the check, so a Linux probe
beside Windows jobs (`CI_SELF_HOSTED_LABEL=windows`) is accepted, while `linux`,
`x64` and `self-hosted` still collide. The narrowing happens on evidence only:
a value that is missing or unrecognized widens that field back to every
candidate, because not knowing the probe's platform is not evidence that it
differs from the one in question.

The two fields narrow **independently**. An unreadable architecture widens the
architecture labels alone and leaves a readable OS narrowed, so a runner known
to be Linux does not get `windows` back merely because its architecture could
not be read. The architecture vocabulary tracks what `RUNNER_ARCH` documents —
`x86`, `x64`, `arm`, `arm64` — because a label *missing* from these sets is not
the safe unrecognized case: it would never be treated as shared at all.

Three limits are worth stating plainly.

**It is a configuration check, not a security boundary.** It catches an operator
who put one label in two variables. It cannot defend a machine that is already
compromised, because it is a repository script that arrives on the runner it is
judging: anything already running there can rewrite it before it executes. What
keeps pull-request code away from the token is registering the probe on its own
machine — the guard only catches the mistakes it can see from inside the job.

It cannot prove that two custom labels name two machines. Nothing inside a
workflow can, without querying the runner registry — which would mean widening
the PAT, the opposite of why any of this exists. Register the probe on its own
machine and the check will catch the mistakes it can see.

And it runs *after* dispatch, so it cannot rescue a `CI_PROBE_LABEL` no runner
answers to. A whitespace-only value satisfies the workflow's `!= ''` condition,
queues the probe job against an unusable label, and never reaches the check at
all — the job simply waits. The check refuses such a value rather than
reporting isolation, which makes `python3 scripts/pick_runner.py
--check-probe-isolation "$CI_PROBE_LABEL"` worth running by hand after changing
it; but a probe that is silently not running is a thing to watch for, not a
thing the guard can catch from inside the job it is guarding.

## Security

A self-hosted runner executes workflow code on your VPS, and unlike a hosted
runner it is not destroyed afterwards — anything a job writes can outlive it.
This repository is private, so only collaborators can trigger a run, which keeps
that exposure to people you already trust.

**If this repository is ever made public**, do not let fork pull requests run on
the VPS: a fork PR would then execute arbitrary code on your machine. Require
approval for outside contributors, or pin fork-triggered jobs to
`ubuntu-latest`.

The token-harvesting path above is the sharper version of the same point, and it
applies *today*, private repository and all. Read that section before enabling
auto mode.

Treat `CI_RUNNER_TOKEN` like any other credential: it can write repository
variables. Nothing in this repository logs it, and the probe passes it by
environment variable rather than interpolating it into a shell command.

## Guard rails

`scripts/switch_runner.py --check` runs in CI and fails the build if any
workflow hardcodes a runner instead of following `CI_RUNNER`. Without it, a
workflow added six months from now would quietly keep burning hosted minutes
while the switch looked like it was on.

The decision logic itself is a script with tests rather than an expression
buried in YAML, per *Deterministic work is not agent work* in `CLAUDE.md`:
choosing a runner from a quota and two thresholds is computable, so it is
computed, and `tests/mutations/ci_runner_*.yaml` proves those tests fail when
the behavior is removed.

## Caveats

- The probe runs on a schedule, so quota can run out between probes. Dispatch it
  by hand (`gh workflow run runner-mode.yml`) or set `CI_RUNNER` directly when
  that happens.
- GitHub disables scheduled workflows in repositories with no activity for 60
  days. If the probe goes quiet, check that first.
- A job already queued for a hosted runner is not moved by a later switch.
