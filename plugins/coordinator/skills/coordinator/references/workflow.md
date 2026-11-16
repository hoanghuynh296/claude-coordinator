# Workflow

The lifecycle below is the same for every project. Where a step says "per the profile", read
`coordination/PROFILE.md`; do not assume a branch name, a role or a merge method.

## 1. Start

**New project** (`/coordinator:kickoff`): interview the owner in one message, draft the plan
and the profile, stop for approval, then create the ledger and whatever the profile needs
(repos, branches, labels, guards). Nothing is created before the owner approves.

**Existing project** (`/coordinator:adopt`): read what is there (repos, branches, CI, open
issues and PRs, any existing notes), propose a profile that matches how the project already
works, stop for approval, then create or migrate the ledger. Adoption changes how work is
tracked, not the product.

Either way, finish by registering the session (`/coordinator:coordinator-register`) and
running `/coordinator:audit` once.

## 2. Plan the next stretch

- `milestone` cadence: `/coordinator:milestone-start <Mn>` turns the milestone's content and
  exit criteria into issues, contract first.
- `continuous` cadence: keep each unit's list in `ROADMAP.md` ordered, with at least the next
  two items as issues (`/coordinator:ticket`).

Every issue has: goal, unit, acceptance criteria, the checks that prove it, what is out of
scope, and what it depends on. An issue that changes a contract between units is done before
the issues on either side of it start.

## 3. Hand out work

One batched message per agent: the issue number, plus the next one or two in order so the
agent does not stop and ask between PRs. Units in `per-issue` mode get a fresh session per
issue instead (brief: `templates/unit-brief.md` plus the issue link).

Sessions can only be started in a turn the owner started from the desktop app. Start every
session the stretch needs in that one turn. If sessions cannot be started (the owner is on
Remote Control, or the tool is unavailable), run the same brief as a background subagent with
its own worktree and convert later.

Never leave a unit idle while its `ROADMAP.md` list has an item that is not blocked.

## 4. The agent's loop (agents do this, not the coordinator)

Fresh branch from the integration branch → commit after each step, push after the first commit
and after every commit → PR that closes the issue → keep the unit's gate green → report once:
"PR ready, gate green" (with the evidence: run id or command output) or "blocked / decision
needed". Before every push the agent checks that the branch's PR is not already merged.

## 5. Review and merge (`/coordinator:review-merge`)

1. Gate green, per the profile. Evidence checked by the coordinator, not taken from the report.
2. Diff inside the unit's ownership and the issue's scope.
3. Reviewer subagent when the profile's risk areas or size limits say so.
4. Manual checks the gate cannot do (per the profile: a browser pass, a run on real hardware).
   If a manual check is skipped, the merge note says `UNVERIFIED: <what>` and the item goes on
   the verification debt list in `ROADMAP.md`.
5. A stacked PR is retargeted to the integration branch before its base merges.
6. Merge with the profile's method. Update the ledger (remove the item; adjust "ahead by").
7. Check the unit's integration limit. At the limit: stop handing out feature issues for that
   unit and go to step 6 of this workflow.

## 6. Verify and release

Who releases each unit is in the profile.

- **Coordinator-released units:** gate green on the integration branch, evidence checked,
  release per the profile (release PR, tag, published artifact). Record it in the ledger.
- **Owner-released units:** prepare the release: what changed in plain words, what was
  verified and how, what is still `UNVERIFIED`, steps for the owner to try. The owner decides.
- `milestone` cadence adds `/coordinator:milestone-close`: QA verdict on the exit criteria,
  demo steps for the owner, then the release.

After a release, clear the unit's verification debt items that the release covered.

## 7. Keep state (continuous)

- Ledger: update, lint, commit and push after every merge, decision, release, session change
  and owner answer.
- Decisions: one row in `DECISIONS.md`; the bound units add their one-line entry.
- Contexts: measure on every owner message; replace any session at the threshold.
- `/coordinator:audit` at least once per working day and before every handover.

## 8. Rotate or stop

- `standing` session at the threshold: it pushes its work, moves what it learned into the
  unit's docs, writes `handover/<unit>.md` (in flight only), then a fresh session with the
  same name starts from that note. Archive the old session; never message it again.
- Coordinator: `/coordinator:handover`, then a fresh session reads `coordination/README.md`
  and registers.
- Usage limit: every agent stops at once. The ledger says who was doing what. After the
  reset, continue each standing agent with one message; start per-issue agents again from
  their issue.
