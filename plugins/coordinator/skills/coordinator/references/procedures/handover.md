# Procedure: Hand over a session

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Write a handover for the named unit or session (none named = this coordinator session). A
handover carries only what is in flight; see `references/state-files.md`.

1. Measure the context (session tools, or
   `bash "<plugin>/scripts/check-context.sh" <session id>`).
2. **A unit's `standing` session:** send it one message asking it to (a) commit and push its
   work, (b) move what it learned about the code into the unit's docs (in its open PR or a
   small docs PR), (c) write `coordination/handover/<unit>.md` in the ledger repo from
   `references/templates/handover.md`, commit and push, (d) reply with the file path. Do not
   write it for the agent. `per-issue` sessions need no handover: the issue and the PR are it.
3. **Yourself:** first make the files true: `COORDINATION.md` (live state, no expired
   delegation), `ROADMAP.md` (order, debt), `DECISIONS.md` (anything decided this session).
   Run the `audit` procedure. Then write `coordination/handover/coordinator.md`: in flight, next
   steps in order, waiting on. If a rule changed, it goes into `PROFILE.md`, not here. Refresh
   `coordination/memory/` from your memory folder (paths relative to the workspace; no home
   paths). Lint, commit and push the ledger.
4. Propose the replacement to the owner in at most 4 lines: a fresh session with the same
   name, first prompt "Read `coordination/README.md` in <ledger> and continue as <role>". A
   fresh coordinator then follows the `coordinator-register` procedure. Archive the old session
   after the new one has started; never message it again.
