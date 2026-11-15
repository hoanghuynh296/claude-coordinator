---
description: Start a milestone - create Issues contract-first, update the ledger, start all lane, Platform and QA sessions in this owner turn
argument-hint: "<milestone e.g. M1>"
---

Start milestone `$ARGUMENTS`. Load the `coordinator` skill; reread `references/pitfalls.md`.

1. From `docs/PLAN.md` section 7 take the milestone's content and QA exit criteria. Split it into
   tickets, one lane each, small enough for one PR. Include: the contract ticket (if the
   milestone adds or changes an interface), one QA ticket (acceptance tests from the exit
   criteria), and Platform tickets for any shared/root file changes (no other ticket may touch
   those).
2. Create each Issue with `/coordinator:ticket` fields (`gh issue create --repo <repo> --title
   "T<m>.<n> <title>" --label lane:<lane> --label milestone:<Mn> --milestone <Mn> --body ...`).
   Order: contract ticket first; backend/frontend tickets that depend on it say "starts after #<contract>"
   and are not handed out until the contract PR merges.
3. Fill the milestone table and the Sessions table in `COORDINATION.md`; commit + push the ledger.
4. **Start every session needed now, in this turn** (sessions can only be started from the owner's
   own message): for each lane with a ready ticket, Platform, and QA - name "Agent: <lane>"
   (QA: "Agent: qa-<Mn>"), the lane's model, its own worktree, background from
   `references/templates/lane-brief.md` / `platform-brief.md` / `qa-brief.md`, prompt = the ticket
   link. Reuse a live lane session by sending it the next ticket instead of starting a new one.
5. If sessions cannot be started (owner on Remote Control, or the tool is unavailable): launch the
   same briefs as background subagents with `isolation: worktree` (they commit every step, push
   after the first commit, open PRs themselves). Mark them `subagent` in the ledger; convert to
   lane sessions when the owner is back at the desktop.
6. Reply to the owner in at most 8 lines: tickets created (numbers), sessions started, what waits on
   the contract, any owner-side task needed for this milestone.
