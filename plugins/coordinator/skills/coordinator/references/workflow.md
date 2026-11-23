# Workflow

The lifecycle below is the same for every project. Where a step says "per the profile", read
`coordination/PROFILE.md`; do not assume a branch name, a role or a merge method.

## 1. Start

**New project** (procedure `kickoff.md`): interview the owner in one message, draft the plan
and the profile, stop for approval, then create the ledger and whatever the profile needs
(repos, branches, labels, guards). Nothing is created before the owner approves.

**Existing project** (procedure `adopt.md`): read what is there (repos, branches, CI, open
issues and PRs, any existing notes), propose a profile that matches how the project already
works, stop for approval, then create or migrate the ledger. Adoption changes how work is
tracked, not the product.

Either way, finish by registering the session (procedure `coordinator-register.md`) and
running procedure `audit.md` once.

## 2. Plan the next stretch

- `milestone` cadence: procedure `milestone-start.md` turns the milestone's content and
  exit criteria into issues, contract first.
- `continuous` cadence: keep each unit's list in `ROADMAP.md` ordered, with at least the next
  two items as issues (procedure `ticket.md`).

Every issue has: goal, unit, acceptance criteria, the checks that prove it, what is out of
scope, and what it depends on. An issue that changes a contract between units is done before
the issues on either side of it start.

## 3. Hand out work

Hand out ONE issue per agent, never a queue of two or three. The agent takes that issue
through its full lifecycle (section 4) and waits; the next issue goes out in the coordinator's
message after the merge (`PR #<n> merged. Next: <issue>`). Units in `per-issue` mode get a
fresh session per issue instead (brief: `templates/unit-brief.md` plus the issue link), unless
the coordinator sends the strict same-session form `PR #<n> merged. Next: #<m> (same session)`
(`review-merge.md` step 9: same unit, context under 175k (or the profile's same-session cap)
measured with the session tools, no session can be started in this turn (Remote Control, an
automated turn, a refused start), no mandatory-Reviewer risk area, fewer than 3 issues in a row
in that session). When a session can be started, the next issue always goes to a fresh one. After the 3rd
issue, or when any condition fails, the next issue goes to a fresh session.

Sessions can only be started in a turn the owner started from the desktop app. Start every
session the stretch needs in that one turn. If sessions cannot be started (the owner is on
Remote Control, or the tool is unavailable), run the same brief as a background subagent with
its own worktree and convert later.

Every session sits at the top level of the sidebar; none nests under another. Start each agent
in its own worktree and detach it right away (`mcp__ccd_session_mgmt__detach_session`). A
nested session builds a chain on every rotation and is archived with its parent. A detached
agent sends no turn-end note to the coordinator, so it reports by message (section 4).

Never leave a unit idle while its `ROADMAP.md` list has an item that is not blocked.

## 4. The agent's loop (agents do this, not the coordinator)

Fresh branch from the integration branch → commit after each step, push after the first commit
and after every commit → PR that closes the issue → local gate (lint and tests) green → report once, by message to the
coordinator session by name ("Coordinator: <project>"): "PR ready" (with the local gate's
evidence, the head SHA and the CI state at that moment: pending, green or red), "blocked /
decision needed", "handover written", or, for an issue with `Draft: required`, "Draft ready"
before the build (`packs/ui-product.md`), ending with `Context: <k tokens>`. The agent reports
as soon as the PR is pushed and the local gate is green; it never waits for CI, because it
runs only when a message arrives and a green CI run sends none. The coordinator owns the CI
wait (section 5). Before every push the agent checks that
the branch's PR is not already merged.

Then the agent waits. It fixes review findings or a red CI when told or woken by Auto-fix
(same branch, reports "PR ready" again with the new head SHA, waits again) and starts nothing new until the coordinator's message `PR #<n> merged. Next: <issue |
handover | stand by | done>`. Sessions run only when a message arrives: an agent that reports
"PR ready, next #50" and ends its turn, and a coordinator that merges and says nothing, leave
both waiting forever. So the coordinator always sends that message in the same turn as the
merge (`review-merge.md`, step 9), and the plugin's Stop hook does not let it end the turn
until it has.

## 5. Review and merge (procedure `review-merge.md`)

1. On every "PR ready", in the same turn: start a background CI watch,
   `scripts/ci-watch.sh <owner/repo> <N> <head sha>` with `run_in_background`. Its exit wakes
   the coordinator when CI ends (green, red or stale-head). Review runs in parallel.
   Gate green, per the profile: the local gate's evidence and CI green on the reported head,
   checked by the coordinator, not taken from the report. Merge only then.
   On "Draft ready" (no merge, no CI watch): the owner reviews the screenshots. Pass change
   requests to the agent; on the owner's approval comment `Draft approved: <date>` on the
   issue, note it in the unit's row and send `Next: build #<n> (same session)`. That is the
   same issue's build phase, not a next issue, so the same-session conditions do not apply.
2. Diff inside the unit's ownership and the issue's scope.
3. Reviewer subagent when the profile's risk areas or size limits say so. Re-run it on fix
   commits in a risk area. Above the line threshold in a risk area, split the work: contract or
   migration PR first, then logic, then UI.
4. Manual checks the gate cannot do (per the profile: a browser pass, a run on real hardware).
   If a manual check is skipped, the merge note says `UNVERIFIED: <what>` and the item goes on
   the verification debt list in `ROADMAP.md`.
5. A stacked PR is retargeted to the integration branch before its base merges.
6. Merge with the profile's method. After merging a `per-issue` agent's PR, archive that
   agent's session (`mcp__ccd_session_mgmt__archive_session`; if refused, call once more with the
   rewritten input, then rename it "<name> (old)" and add it to the one owner line "Archive
   finished sessions: <names>"); a `standing` session is archived only on rotation. Fallback only while the app setting `auto_archive_on_pr_close` is still
   on: check `mcp__ccd_pr__get_status` and unbind (`mcp__ccd_pr__unbind_pr`) any PR bound to you.
   Update the ledger (remove the item; adjust "ahead by"). In the same turn, read the author's
   context (`mcp__ccd_session_mgmt__get_usage`) and send it `PR #<n> merged. Next: <issue |
   handover | stand by | done>` (`review-merge.md`, step 9). Without `(same session)` a
   `per-issue` agent gets `Next: done` and is archived.
7. Check the unit's open release group and its safety ceiling. Group complete: go to step 6
   of this workflow for that group. Ceiling reached (default 2 weeks or 15 PRs): stop handing
   out feature issues for that unit; split the group and release what is complete and
   verified, or finish the group first.

## 6. Verify and release

Who releases each unit is in the profile.

- **Coordinator-released units:** gate green on the integration branch, evidence checked,
  release per the profile (published artifact, record in the ledger). With a `develop`, a
  release is: branch `release/vX.Y.Z` from `develop` → PR into `main` → tag → back-merge `main`
  into `develop`. `develop` is never a PR head (delete-branch-on-merge would remove it). Merge the release PR
  with a merge commit, not a squash. The coordinator's own PRs use heads `release/vX.Y.Z`,
  `backmerge/vX.Y.Z` or `coordinator/<topic>`; the Next guard skips exactly those.
- **Owner-released units:** prepare the release: what changed in plain words, what was
  verified and how, what is still `UNVERIFIED`, steps for the owner to try. The owner decides.
- `milestone` cadence adds procedure `milestone-close.md`: QA verdict on the exit criteria,
  demo steps for the owner, then the release.

After a release, clear the unit's verification debt items that the release covered.

## 7. Keep state (continuous)

- Ledger: update, lint, commit and push after every merge, decision, release, session change
  and owner answer.
- Decisions: one row in `DECISIONS.md`; the bound units add their one-line entry.
- Contexts: measure on every owner message. `SOFT`: no new issue for that session; replace it
  after its current PR. `HARD`: replace it now (section 8).
- procedure `audit.md` at least once per working day and before every handover.

## 8. Rotate or stop

- **Soft threshold** (default 250k for agents, 300k for the coordinator): the session does not stop mid-task. It finishes its
  current issue (PR, gate green), takes no new one, moves what it learned into the unit's
  docs and writes `handover/<unit>.md` (in flight only) **before that PR merges**: a session
  whose last PR merged may be archived by the app, and its context is lost.
- **Hard threshold** (default 400k, or 75% of the model's window if lower, for agents; 450k
  for the coordinator): it stops at the
  next safe point (commit, push), writes a full handover (done, left in order, decisions,
  commands to re-run, traps) and reports "blocked: rotate". No new step.
- Then a fresh session with the same name starts from that note. It is never started by the
  session it replaces: the coordinator starts it and detaches it to the top level. The old
  session is renamed "<name> (old)" or archived before the new one takes the name. Archive the old session;
  never message it again.
- `per-issue` sessions write no handover file: at soft they just finish the issue; at hard
  they write done, left, commands to re-run and traps into the PR (or the issue if there is no
  PR yet), and the next session for that issue starts from it.
- Coordinator: procedure `handover.md`, then a fresh session, started by the old coordinator
  and detached or started by the owner from the sidebar, reads `coordination/README.md` and
  registers: it takes the name "Coordinator: <project>" only after the old coordinator is
  renamed "Coordinator: <project> (old)" or archived, then sends every live agent one message
  with its name.
- Usage limit: every agent stops at once. The ledger says who was doing what. After the
  reset, continue each standing agent with one message; start per-issue agents again from
  their issue.

## Measuring and cross-project items

- Context is measured with the session tools (`get_usage`, `scripts/check-context.sh`); an
  agent's self-report is a hint, never the measure.
- A cross-project item lives in the producer's ledger; the consumer's ledger writes
  "waits on <project>#N" and nothing more.
