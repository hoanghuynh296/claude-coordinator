# Procedure: Audit the coordination state

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Audit the project's coordination state. Run this once per
working day, before every handover, and whenever the ledger feels wrong.

1. **Mechanical lint:**
   `bash "<plugin>/scripts/ledger-lint.sh" <ledger-dir>`
   Fix every error (the message names the file and the rule). If the ledger repo has no
   `coordinator-kit ledger-lint pre-commit` hook (`.git/hooks/pre-commit`), install it:
   `bash "<plugin>/scripts/install-guards.sh" <ledger-dir>` (also after a plugin upgrade). Typical fixes: delete finished
   items from `COORDINATION.md`; move a rule to `PROFILE.md`; add a missing decision row;
   remove a session id or a home path.
2. **Drift against GitHub**, per unit repo: open PRs and open `task` issues against the
   ledger's "In progress" and the roadmap's lists; how far the integration branch is ahead of
   the release branch (`gh api repos/<repo>/compare/<release>...<integration> --jq .ahead_by`)
   against the ledger's "Integration ahead by". GitHub is right; fix the ledger.
3. **Release groups and ceilings:** every open issue sits in a group; any unit past its safety
   ceiling (default 2 weeks or 15 PRs) and still receiving feature issues? Stop them; split
   the group and release what is complete and verified, or finish the group. A group that
   is complete and unreleased is the next item.
4. **Idle units:** any unit with an unblocked backlog item and nobody on it? Hand it out in
   the next batched message (or say why not, for example an owner-set pause).
5. **Backlog depth:** every unit has at least its next two items as issues, or its list says
   "nothing planned".
6. **Verification debt:** every `UNVERIFIED` in recent merge notes has a row; rows a release
   has covered are removed.
7. **Delegations:** every entry under "Active delegations" has a date and is still valid;
   delete the rest.
8. **Decisions:** anything decided since the last audit has a row in `DECISIONS.md`; units a
   new decision binds have (or have an issue for) their one-line entry.
9. **One home per fact:** a rule that appears in two files is deleted from all but
   `PROFILE.md`. Knowledge about a unit's code found in a handover note moves to that unit
   (an issue or a docs PR).
10. **Profile fit:** does a recurring problem point at a profile choice
    (`references/profile.md`, "Changing the profile")? Propose one change to the owner.
    **Owner merge asks:** `PROFILE.md` has the line `Owner approves merges into:` and a model
    per runtime in every unit row (missing → add them: `none`, the models in use, and a
    `DECISIONS.md` row). Every ask since the last audit for the owner's leave to merge into a
    branch that line does not name (the owner queue in `COORDINATION.md`, your messages) is a
    finding: drop it from the queue, merge per `review-merge.md`, report how many.
11. **Sessions:** the app setting `auto_archive_on_pr_close` is off
    (`mcp__ccd_settings__get_settings`; on → ask the owner to turn it off). No `per-issue`
    agent session is still live after its PR merged; archive it
    (`mcp__ccd_session_mgmt__archive_session`; archive procedure in `references/sessions.md`).
    The owner queue holds at most ONE line "Archive finished sessions: <names>" (merge several
    into one; never one item each), and no session named "(old)" is still working: one that is
    working was renamed by mistake, so rename it back or stop it.
12. **Pending starts:** every line under "Pending starts" in `COORDINATION.md` was added in
    the latest owner turn; one older than that is reported to the owner and started in this
    turn when it is owner-started (staffing caps in `references/sessions.md`), else kept.
13. **Worktrees** (once per working day): save `mcp__ccd_session_mgmt__list_sessions`
    (`include_archived: false`, `limit: 200`; it returned exactly `limit` rows → raise `limit`
    and list again, so no live session is missing) as JSON to a scratch file, then
    `bash "<plugin>/scripts/prune-worktrees.sh" <each unit repo> --sessions <file> --apply`
    (a group coordinator: over the group's root folder). It removes only finished worktrees:
    unchanged for 6 hours, clean, pushed, no live session in it or on its branch, and no open
    PR for its branch (`gh`; a failed lookup keeps it). Report the space freed;
    a `KEEP` that is a finished session's unpushed or dirty work goes to its unit (an issue or a
    message), a `STRAY` folder to the owner. Generated files a unit's tools write into a
    worktree (for example `apps/*/AGENTS.md`) go in the profile and are passed as `--discard`.
14. **Kit upgrade** (per project; also when a kit release message arrives):
    - **Running kit:** the SessionStart line `Coordinator kit <v>`. A line `... <new> is
      installed: rotate this session at the next safe point` (at a start, resume, compaction
      or owner turn) → rotate (`handover.md`, then a
      replacement) at the next owner desktop turn; agents on the old kit rotate once their PR
      is merged. Installed older than the newest release (`gh release view --repo
      hoanghuynh296/claude-coordinator --json tagName`; Antigravity: `ag-install.sh --check`
      says `STALE`) → tell the kit's coordinator (Semi Group: "Coordinator: Semi Group Tech").
    - **Ledger repo:** the ledger-lint pre-commit hook (step 1).
    - **Each unit repo:** `.claude/lean-tools.lock.json` is committed (missing → the lean-tools
      step: `install-guards.sh --tools "<the unit's Tools groups>" <unit>`, with
      `--adopt-existing` when `settings.json` already holds catalog entries, through a PR), and
      `git config coordinator.reportTo` is set in its clone (missing →
      `install-guards.sh --agent <project> <unit>`).
    - **Missing upgrade steps:** `COORDINATION.md` line `Kit: <x.y.z>` names the newest release
      whose steps this project has done (missing line → assume the oldest kit you can prove,
      else 0.10.0). List every **Upgrade** item of README "Changes" for each later release
      that is not done, do them (owner-only ones go to the owner queue), then set `Kit:` to the
      release they reach. Report: running kit, `Kit:`, the steps done and the steps left.

Commit the ledger (`ledger-commit.sh`). Report in at most 8 lines: what was wrong, what you fixed, what
needs the owner.
