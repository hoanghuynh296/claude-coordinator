---
description: Register this session as the coordinator of an existing project (enables the guard hook and SessionStart reminder)
argument-hint: "<ledger-dir> [project-dir]"
---

Register this session as coordinator. Arguments: `$ARGUMENTS`.

1. If no ledger dir was given, ask the owner for the local path of the `<project>-coordination`
   ledger repo (the one with `COORDINATION.md`) and the project repo path. Wait for the answer.
2. If the ledger repo does not exist yet, ask the owner, then create it next to the project
   (creates the private `<repo>-coordination`, `COORDINATION.md` from the template, `handover/`;
   touches nothing else):
   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh" <owner/repo> <project-dir> --ledger-only
   ```
   Then fill the ledger from the current state (open Issues/PRs, running sessions).
3. Run:
   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/register.sh" "${CLAUDE_SESSION_ID}" <ledger-dir> <project-dir>
   ```
4. Read `COORDINATION.md` and the newest note in `handover/`, load the `coordinator` skill, and
   give the owner a status in at most 8 lines (as `/coordinator:status` would).

To stop being coordinator: `"${CLAUDE_PLUGIN_ROOT}/scripts/register.sh" --unregister "${CLAUDE_SESSION_ID}"`.
