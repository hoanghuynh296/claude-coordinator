# Procedure: Hand over a session

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Write a handover for the named unit or session (none named = this coordinator session). A
handover carries only what is in flight; see `references/state-files.md`.

1. Measure the context (session tools, or
   `bash "<plugin>/scripts/check-context.sh" <session id>`). `SOFT`: send it no new issue and
   let it finish the current one; the handover is due before that PR merges. `HARD`: now.
   Either way the note must exist before the session's last PR merges, since a session whose
   PR merged may be archived by the app.
2. **A unit's `standing` session:** send it one message asking it to (a) at `SOFT`, finish the
   current issue first (PR, gate green; at `HARD`, stop at the next safe point), commit and push
   its work, (b) move what it learned about the code into the unit's docs (in its open PR or a
   small docs PR), (c) write `coordination/handover/<unit>.md` in the ledger repo from
   `references/templates/handover.md` (at `HARD` fill every section: done, left in order,
   decisions, commands to re-run, traps), commit and push, (d) report "handover written" with
   the file path, by message to "Coordinator: <project>". Do not
   write it for the agent. `per-issue` sessions write no handover file: at `SOFT` they just finish the issue; at `HARD`
   they write done, left, commands to re-run and traps into the PR (or the issue if there is
   no PR yet), which the next session starts from.
3. **Yourself:** first make the files true: `COORDINATION.md` (live state, no expired
   delegation), `ROADMAP.md` (order, debt), `DECISIONS.md` (anything decided this session).
   Run the `audit` procedure. Then write `coordination/handover/coordinator.md`: in flight, next
   steps in order, waiting on. If a rule changed, it goes into `PROFILE.md`, not here. Refresh
   `coordination/memory/` from your memory folder (paths relative to the workspace; no home
   paths). Lint, commit and push the ledger.
4. Propose the replacement to the owner in at most 4 lines: a fresh session with the same
   name, first prompt "Read `coordination/README.md` in <ledger> and continue as <role>". It is
   never started by the session it replaces: an agent's replacement is started by the
   coordinator; a coordinator's by the old coordinator, or by the owner from the sidebar. The
   starter detaches it to the top level right away (`mcp__ccd_session_mgmt__detach_session`);
   if that is refused, the new session detaches itself (`self`) or the owner drags it out. A
   fresh coordinator then follows the `coordinator-register` procedure. Before archiving the
   old coordinator, unbind every PR from it and check that no session still nests under it.
   Archive the old session after the new one has started; never message it again.
