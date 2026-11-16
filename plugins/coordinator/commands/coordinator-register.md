---
description: Register this session as the coordinator of a project (enables the edit guard and the SessionStart reminder)
argument-hint: "<ledger-dir> [unit-dir...]"
---

Register this session as coordinator. Arguments: `$ARGUMENTS`.

1. No ledger dir given: ask the owner for the local path of the ledger repo (the one with
   `COORDINATION.md`). No ledger at all: run `/coordinator:adopt` or `/coordinator:kickoff`.
2. Read `coordination/PROFILE.md`, section "Coordinator edit policy". Build the command:
   ```sh
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/register.sh" "${CLAUDE_SESSION_ID}" <ledger-dir> <unit-dir>... \
     --allow '<glob relative to a unit>' --allow '<glob>'
   ```
   - One `<unit-dir>` per unit checkout. In a `multi-repo` workspace these are folders inside
     the ledger dir (`products/<unit>`); the guard still treats them as units.
   - `--allow` once per path the profile lets the coordinator edit inside units. Without any
     `--allow` the defaults apply: `docs/PLAN.md`, `docs/adr/*`, `docs/contracts/README.md`,
     `AGENTS.md`.
   - `--allow-none` when the profile lets the coordinator edit nothing inside units.
   - `--no-guard` only when the profile says the coordinator may write code.
3. Follow the read order in `coordination/README.md`, load the `coordinator` skill, and give
   the owner a status in at most 8 lines (as `/coordinator:status` would).

To stop being coordinator:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/register.sh" --unregister "${CLAUDE_SESSION_ID}"`.
