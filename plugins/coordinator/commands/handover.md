---
description: Write a handover note for a session (default this coordinator) into the ledger repo and propose rotation
argument-hint: "[session name]"
---

Write a handover for `$ARGUMENTS` (empty = this coordinator session).

1. Measure context: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-context.sh" ${CLAUDE_SESSION_ID}` (or the
   given session's id from the ledger Sessions table).
2. For another session: send it one message asking it to write its handover note from
   `references/templates/handover.md` into the ledger repo `handover/<date>-<slug>.md`, commit and
   push its own work first, and reply with the file path. Do not write it for them.
3. For yourself: fill `references/templates/handover.md` -> `<ledger>/handover/<YYYY-MM-DD>-coordinator.md`.
   Include open PRs and their state, sessions and their tickets, pending owner questions, next
   steps in order, gotchas. Update `COORDINATION.md` (Sessions table: last handover). Commit + push
   the ledger.
4. Propose the rotation to the owner in at most 4 lines: start a fresh session with the same name,
   first prompt "Read <ledger>/COORDINATION.md and <handover file>, then continue as <role>". For the
   coordinator the fresh session must run `/coordinator:coordinator-register <ledger> <project>`.
