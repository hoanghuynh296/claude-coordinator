# Procedure: Review and merge a pull request

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Review and merge the named pull request. Read the unit's row and the
"Review" section of `coordination/PROFILE.md` first.

1. `gh pr view <n> --repo <repo> --json title,state,baseRefName,headRefName,mergeable,statusCheckRollup,files,additions,deletions,closingIssuesReferences,body`
   - Already merged or closed → stop and say so.
   - Base is not the integration branch (a stacked PR) → `gh pr edit <n> --base <integration>`
     before merging anything under it.
2. **Gate.** The unit's gate from the profile must be green for this head commit. Look at the
   evidence yourself (the check run, or run the command in a scratch worktree, never in the
   agent's checkout). A gate the CI does not cover and nobody ran is not green.
3. **Scope.** The diff stays inside the unit's ownership and the issue's scope. Otherwise
   send it back.
4. **Reviewer.** Mandatory when the diff touches a risk area or exceeds the size limit in the
   profile. Spawn `coordinator:reviewer` with the repo, PR number, issue link, risk area and
   the packs that apply. Otherwise review the diff yourself against
   `references/review-checklist.md` plus the profile's packs.
   - Blocking findings → one batched message to the agent; stop until it reports again.
   - Non-blocking → a new issue, or a line under "Ideas" in `ROADMAP.md`.
5. **Manual checks** the profile lists for this unit (for example a browser pass). Done → say
   what you checked. Not done → the merge is allowed only if the profile defers that check to
   release time; then add a row to "Verification debt" in `ROADMAP.md`.
6. **Merge** with the profile's method, deleting the branch:
   `gh pr merge <n> --repo <repo> --merge --delete-branch` (or `--squash`).
   - The author is a `per-issue` agent: archive its session now
     (`mcp__ccd_session_mgmt__archive_session`, found by name "Agent: <unit> #<issue>"). Its
     work is in the PR; anything left for a next session is in the PR or the issue.
   - The author is a `standing` session: leave it running; it is archived only on rotation.
   - Fallback, only while the app setting `auto_archive_on_pr_close` is still on: the app has
     bound this PR to your session (any `gh` touch binds it) and archives you when it closes.
     Check `mcp__ccd_pr__get_status`, unbind (`mcp__ccd_pr__unbind_pr`) every merged PR bound to you,
     and ask the owner again to turn the setting off.
7. **Ledger.** Update the unit's row in `COORDINATION.md` (in progress, "integration ahead
   by"); remove the issue from `ROADMAP.md`. Do not add a line about the merged PR. Lint,
   commit and push.
8. **Limit.** If the unit is now at its integration limit, the next thing you hand out for it
   is verification and release, not a feature.
9. Tell the agent nothing about the merge (it checks PR state itself). Reply to the owner
   only if a decision is needed; otherwise at most 3 lines.
