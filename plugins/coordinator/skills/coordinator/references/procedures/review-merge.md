# Procedure: Review and merge a pull request

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Review and merge the named pull request. Read the unit's row and the
"Review" section of `coordination/PROFILE.md` first.

1. `gh pr view <n> --repo <repo> --json title,state,baseRefName,headRefName,headRefOid,mergeable,statusCheckRollup,files,additions,deletions,closingIssuesReferences,body`
   - Already merged or closed → stop and say so.
   - Base is not the integration branch (a stacked PR) → `gh pr edit <n> --base <integration>`
     before merging anything under it.
2. **Start the CI watch, in this turn.** Agents report "PR ready" on push, with the local gate
   green, the head SHA and the CI state; they never wait for CI. A green CI run wakes nobody,
   so you own the wait. On every "PR ready" (the first and each one after fixes) start, with
   the Bash tool's `run_in_background`:
   `bash "<plugin>/scripts/ci-watch.sh" <owner/repo> <n> <head sha>`
   Its exit wakes you with one line: `green`, `red: <checks> <link>`, `stale-head` (the head
   moved: wait for the agent's next report), `timeout`, `no-checks` or `error`. Then go on
   with steps 3 to 5 in parallel; do not wait for CI to review. Already green in step 1's
   `statusCheckRollup` for the reported head → no watch needed.
   - `red` → one message to the agent: the failing checks and the link (skip it if Auto-fix
     already woke the agent on this failure). It fixes, reports "PR ready" again; start a new
     watch for the new head.
   - `timeout` or `no-checks` → check the runner (`gh run list --repo <repo> --limit 5`);
     a stuck runner is an owner task; start the watch again once it runs.
   **Gate.** The unit's gate from the profile must be green for this head commit: the local
   part from the agent's evidence, CI from the watch's `green` (or the check runs) for the
   reported head, never from the report alone. Look at the evidence yourself (or run the
   command in a scratch worktree, never in the agent's checkout). A gate the CI does not cover
   and nobody ran is not green.
3. **Scope.** The diff stays inside the unit's ownership and the issue's scope. Otherwise
   send it back.
4. **Reviewer.** Mandatory when the diff touches a risk area or exceeds the size limit in the
   profile (default: over 400 changed lines or over 25 hand-written files, not counting
   `CHANGELOG.md`, `VERSION`, `package*.json`, lockfiles, `public/**` mirrors, `**/vendor/**`
   and the profile's additions to that list). A release PR is exempt from the size limit when
   every feature PR in it passed review. Spawn `coordinator:reviewer` with the repo, PR number, issue link, risk area and
   the packs that apply. Otherwise review the diff yourself against
   `references/review-checklist.md` plus the profile's packs.
   - Blocking findings → one batched message to the agent (with a red CI's failures, if the
     watch has ended red); stop until it reports again. It fixes them on the same branch,
     reports "PR ready" again and waits again; review that report from step 1 and start a new
     CI watch for the new head (step 2).
   - Fix commits in a risk area: run the Reviewer again on the fix commits before merging.
   - Above the Reviewer line threshold in a risk area, send the work back to be split: the
     contract or migration PR first, then the logic, then the UI.
   - A cross-lane mini-exception (a small change in another lane's file) is allowed only if the
     issue names it; the Reviewer checks it.
   - Non-blocking → a new issue, or a line under "Ideas" in `ROADMAP.md`.
5. **Manual checks** the profile lists for this unit (for example a browser pass). Done → say
   what you checked. Not done → the merge is allowed only if the profile defers that check to
   release time; then add a row to "Verification debt" in `ROADMAP.md`.
6. **Merge** only when CI is green on the reported head (step 2) and the review passed
   (steps 3 to 5), with the profile's method, deleting the branch:
   `gh pr merge <n> --repo <repo> --merge --delete-branch --match-head-commit <head sha>`
   (or `--squash`). Pass a literal PR number; `--match-head-commit` refuses the merge if the
   head moved after what you reviewed. With `--auto` the merge may only be queued: the hook records the PR only once it
   is MERGED, so see step 9.
   - **Close the linked issue.** "Closes #N" fires only when a PR merges into the default
     branch, so after merging into an integration branch other than it (`develop`) run
     `gh issue close <N> --repo <repo> --comment "Merged in #<n>"`. Release PRs
     (`release/*`), back-merge PRs (`backmerge/*`) and PRs you opened yourself get no `Next:`
     message: the Next guard skips heads `release/*`, `backmerge/*` and `coordinator/*`, so name
     every branch you open yourself `coordinator/<topic>`.
   - The author is a `per-issue` agent: send it `PR #<n> merged. Next: done` (step 9), then
     archive its session (but if step 9 allows `Next: #<m> (same session)`, send that and archive
     nothing)
     (`mcp__ccd_session_mgmt__archive_session`, found by name "Agent: <unit> #<issue>"; if it is
     refused, follow the archive procedure in SKILL.md "Sessions": call once more with the
     rewritten input, then rename "<name> (old)" and add it to the one owner line "Archive finished
     sessions: <names>"). Its
     work is in the PR; anything left for a next session is in the PR or the issue.
   - The author is a `standing` session: leave it running; it is archived only on rotation.
   - Fallback, only while the app setting `auto_archive_on_pr_close` is still on: the app has
     bound this PR to your session (any `gh` touch binds it) and archives you when it closes.
     Check `mcp__ccd_pr__get_status`, unbind (`mcp__ccd_pr__unbind_pr`) every merged PR bound to you,
     and ask the owner again to turn the setting off.
7. **Ledger.** Update the unit's row in `COORDINATION.md` (in progress, "integration ahead
   by"); remove the issue from `ROADMAP.md`. Do not add a line about the merged PR. Lint,
   then commit and push once at the end of your turn, together with every other ledger change
   of that turn (several merges in one turn: one commit).
8. **Group and ceiling.** Check the unit's open release group in `ROADMAP.md`: all its issues
   merged and its debt rows verifiable → the next thing for that unit is `milestone-close`
   for the group (urgent patches go at once). Then check the safety ceiling (profile "Release"
   column; default 2 weeks or 15 PRs ahead of the last release): reached → no new feature
   issue for that unit; split the group and release what is complete and verified, or finish
   the group. The ceiling alone never releases; a half-done large group is not shipped.
9. **Tell the author what is next, in the same turn as the merge.** The agent waits after
   "PR ready" and runs only when a message arrives, so silence here stalls it for good.
   First check any merge you queued with `--auto`:
   `gh pr view <n> --repo <repo> --json state,autoMergeRequest`. Still queued → send nothing
   yet (the agent keeps waiting) and look again on your next turn; MERGED → go on.
   Read its context (`mcp__ccd_session_mgmt__get_usage` on its session; its last report's
   `Context:` line is the fallback), then send it one message:
   `PR #<n> merged. Next: <issue | handover | stand by | done>`.
   - At or past the soft threshold → `Next: handover` (a `standing` session writes its
     handover and is replaced; no new issue).
   - A `per-issue` agent → `Next: done`, then archive its session (step 6), unless ALL of these
     hold; then send `PR #<n> merged. Next: #<m> (same session)` and do not archive it:
     (1) `#m` is in the same unit; (2) the agent's context, measured with
     `mcp__ccd_session_mgmt__get_usage` or `scripts/check-context.sh` (not self-reported), is
     under the same-session cap (default 175k, or the profile's Budgets line); (3) you cannot
     start a session in this turn (the owner is on Remote Control, an automated turn, or
     `start_session` was refused): when you can start one, `#m` goes to a fresh session;
     (4) `#m` is not in a risk area where the profile makes the Reviewer mandatory; (5) the session has done fewer than 3 issues in a row (count
     the ones you handed it, this one included). Any condition fails, or this was its 3rd issue
     → `Next: done` and `#m` goes to a fresh session. Without `(same session)` the agent stops.
     Record the count in the ledger's unit row ("Agent: <unit> #<m>, issue k/3") each time you
     send a Next, so it survives a coordinator rotation; an unknown count counts as a failed
     condition (5): the next issue goes to a fresh session.
   - Otherwise the next issue from its `ROADMAP.md` list (`Next: #<m> <link>`), or
     `Next: stand by` if nothing unblocked is left.
   The plugin's Stop hook blocks the end of your turn while a merged PR has no such message.
   If the author can no longer receive one (its session was archived or deleted), clear it
   with a reason the ledger keeps:
   `bash "<plugin>/scripts/next-clear.sh" <session> <owner/repo#n> "<reason>"`.
   The hook clears a PR on any message you send that holds `PR #<n> merged` and a `Next:`
   line, whoever receives it: send it to the author only. When the same number is pending in
   two repos, write `PR <owner/repo>#<n> merged. Next: ...`.
   Reply to the owner only if a decision is needed; otherwise at most 3 lines.
