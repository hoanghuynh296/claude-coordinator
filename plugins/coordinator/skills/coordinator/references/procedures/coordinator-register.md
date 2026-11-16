# Procedure: Register this session as the coordinator

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Register this session as coordinator. Input: the ledger folder and, optionally, the unit folders.

1. No ledger dir given: ask the owner for the local path of the ledger repo (the one with
   `COORDINATION.md`). No ledger at all: follow the `adopt` procedure (existing project) or the `kickoff` procedure (new project).
2. Read `coordination/PROFILE.md`, section "Coordinator edit policy". Build the command:
   ```sh
   bash "<plugin>/scripts/register.sh" "<session>" <ledger-dir> <unit-dir>... \
     --allow '<glob relative to a unit>' --allow '<glob>'
   ```
   - One `<unit-dir>` per unit checkout. In a `multi-repo` workspace these are folders inside
     the ledger dir (`products/<unit>`); the guard still treats them as units.
   - `--allow` once per path the profile lets the coordinator edit inside units. Without any
     `--allow` the defaults apply: `docs/PLAN.md`, `docs/adr/*`, `docs/contracts/README.md`,
     `AGENTS.md`.
   - `--allow-none` when the profile lets the coordinator edit nothing inside units.
   - `--no-guard` only when the profile says the coordinator may write code.
3. Follow the read order in `coordination/README.md` and load the `coordinator` skill.
4. Make sure this session sits at the top level of the sidebar: if it nests under the session
   that started it, detach yourself (`mcp__ccd_session_mgmt__detach_session` with `self`), or
   ask the owner to drag it out. Unbind any PR bound to this session that is already merged
   (`mcp__ccd_pr__unbind_pr`).
5. Taking over from another coordinator: send every live agent one message, "Coordinator is
   now the session 'Coordinator: <project>'; report to it by message." Nothing else in it.
6. Give the owner a status in at most 8 lines (as the `status` procedure would).

To stop being coordinator:
`bash "<plugin>/scripts/register.sh" --unregister "<session>"`.
