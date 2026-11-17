# Roles

Three roles exist in every project. The rest are optional and are switched on in the
project's `PROFILE.md` (see `profile.md` for when each one pays).

## Always

| Role | Kind | Does | Never does |
|---|---|---|---|
| Owner | human | approves the plan and the profile; answers real decisions; approves anything that costs money; releases the units the profile marks owner-released; does non-code tasks (accounts, secrets, billing) | receives status pings or ack-only messages |
| Coordinator | one Claude session | keeps the ledger, roadmap and decisions; writes issues; starts and briefs agents; reviews; on every "PR ready" starts a background CI watch (`scripts/ci-watch.sh`) and merges only on green CI for the reported head; merges into the integration branch, tells the author `PR #<n> merged. Next: ...` in the same turn, and archives the `per-issue` agent's session; detaches every session it starts to the top level; releases the units the profile gives it; reports to the owner | writes product code (unless the profile says so); does agents' git plumbing; does for an agent what that agent's permissions denied |
| Unit agent | Claude session, `standing` or `per-issue` | owns one unit; one branch and one PR per issue; keeps its gate green; moves what it learns into the unit's docs; reports "PR ready" once per push that needs review (local gate green, head SHA, CI state; never waiting for CI), by message to "Coordinator: <project>", then waits for `PR #<n> merged. Next: ...`; one issue at a time | edits another unit's files; merges its own PR; decides anything that costs money |

## Optional

| Role | Kind | Does | Never does |
|---|---|---|---|
| Platform | unit agent | sole owner of shared and root files: CI, build files, workspace files, infra, deploy | product features |
| QA | session per milestone | writes acceptance tests from the exit criteria before the code exists; runs them after merges; gives the milestone verdict | product code |
| Reviewer | read-only subagent `coordinator:reviewer` | independent review of risky or large PRs; verdict and ranked findings in at most 15 lines | edits, pushes, comments on GitHub |
| One-off builder | subagent `coordinator:oneoff-builder` | a self-contained task outside any unit's queue (docs, fixtures, an investigation); pushes its own branch and opens a PR | long-lived ownership |

## Why these splits

- **The coordinator keeps its context for coordination.** Its context holds the plan, every
  open issue and every review. Code, logs and git plumbing fill it fast and force an early
  rotation. Where the profile forbids coordinator edits, the guard hook enforces it.
- **Agents report on push; the coordinator owns the CI wait.** A session runs only when a
  message arrives, and a green CI run sends nobody one (Auto-fix wakes an agent on CI failure
  only). An agent that waits for CI before reporting is never woken when CI passes. So the
  agent reports "PR ready" once its local gate is green, with the head SHA and the CI state,
  and the coordinator starts a background watch whose exit wakes it when CI ends.
- **One issue, one full lifecycle.** An agent runs only when a message arrives. It works on the
  one issue it was given, reports "PR ready", and waits; the coordinator's message after the
  merge (`PR #<n> merged. Next: ...`) is what starts its next step. Nothing else wakes it.
- **Sessions are peers, not a tree.** Every session sits at the top level of the sidebar, so a
  rotation or an archive touches one session only. The price: no turn-end notes, so every
  report is a message to the coordinator by name.
- **Review is independent of the author.** The author's tests encode the author's
  assumptions. Independent review has caught high-severity bugs that CI and dozens of
  author-written tests missed.
- **Platform exists only where shared files hurt.** If PRs do not conflict on root files, the
  role is overhead.
- **QA writes acceptance first.** Tests written from the exit criteria before the code exists
  cannot be bent to fit the implementation.

## Models

The profile records the model and effort per role. A common split: the stronger model where
mistakes are expensive or reasoning is deep (coordinator, Reviewer, a core unit), the cheaper
one for well-specified work (docs, integrations, Platform, QA, one-offs). Revisit the split
when usage limits bite: four strong-model sessions in parallel drain a plan quickly.
