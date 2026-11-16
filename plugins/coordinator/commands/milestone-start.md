---
description: Start a milestone or a planned stretch of work - create the issues contract-first, order the backlog, and start or brief every agent it needs in this owner turn
argument-hint: "<milestone, e.g. M1, or a short name for the stretch>"
---

Start `$ARGUMENTS`. Load the `coordinator` skill; reread `references/pitfalls.md`.

1. Take the content and exit criteria from `coordination/ROADMAP.md` (milestone cadence) or
   the top of each unit's backlog (continuous cadence). Split it into issues, one unit each,
   each small enough for one PR. Include:
   - the contract issue first, if the stretch adds or changes an interface between units;
   - a QA issue (acceptance tests from the exit criteria) when the profile has QA on;
   - Platform issues for shared or root files when the profile has Platform on.
2. Create each issue with `/coordinator:ticket`. Issues that depend on the contract say
   "depends on #<n>" and are not handed out until it merges.
3. Order each unit's list in `ROADMAP.md`. Update `COORDINATION.md` (in progress per unit).
   Lint, commit and push the ledger.
4. **Staff it now, in this turn** (sessions can only be started from the owner's own message):
   - `standing` units with a live session: one batched message with the next two or three
     issues, in order.
   - `standing` units without a session, and `per-issue` units: start a fresh session, named
     per the profile, with the model and effort from the profile, background from
     `references/templates/unit-brief.md` (plus `platform-brief.md` / `qa-brief.md`), prompt =
     the issue links.
   - Cannot start sessions (owner on Remote Control, or the tool is unavailable): launch the
     same briefs as background subagents with their own worktree; convert to sessions when the
     owner is back at the desktop.
5. Reply to the owner in at most 8 lines: issues created (numbers), who is doing what, what
   waits on the contract, any owner-side task this stretch needs.
