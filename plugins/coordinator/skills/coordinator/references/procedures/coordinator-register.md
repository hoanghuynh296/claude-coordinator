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
   - `--no-guard` only when the profile says the coordinator may write code, or when sessions
     cannot be started and builder subagents must write in their worktrees (they inherit this
     session's guard). In that second case the coordinator still writes no unit code itself,
     and re-registers with the guard on once sessions can be started again.
3. Follow the read order in `coordination/README.md` and load the `coordinator` skill.
4. Make sure this session sits at the top level of the sidebar: if it nests under the session
   that started it, detach yourself (`mcp__ccd_session_mgmt__detach_session` with `self`), or
   ask the owner to drag it out.
5. Read the app settings (`mcp__ccd_settings__get_settings`). If `auto_archive_on_pr_close` is
   on, ask the owner to turn it off (`mcp__ccd_settings__set_setting`; the owner approves the
   change): the app binds every PR a session touches with `gh` and archives the session when
   that PR closes, which would archive the coordinator after a merge. Record the result in
   `PROFILE.md` ("Flow": the setting's state and the date checked). While it stays on, unbind
   every merged PR still bound to this session (`mcp__ccd_pr__get_status`,
   `mcp__ccd_pr__unbind_pr`).
6. Name this session "Coordinator: <project>" (`mcp__ccd_session_mgmt__set_session_title`
   with `self`), then check with `mcp__ccd_session_mgmt__list_sessions` that it is the only
   live session with that name. Another one (an old coordinator) must be renamed
   "Coordinator: <project> (old)" or archived first; agents report by name, and a report to
   the wrong session is lost. This step also runs at the end of `kickoff` and `adopt`.
7. Taking over from another coordinator: send every live agent one message, "Coordinator is
   now the session 'Coordinator: <project>'; report to it by message." Nothing else in it.
8. Give the owner a status in at most 8 lines (as the `status` procedure would).

To stop being coordinator:
`bash "<plugin>/scripts/register.sh" --unregister "<session>"`.
