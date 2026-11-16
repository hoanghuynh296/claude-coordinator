---
description: Review and merge an agent's PR - check the gate evidence and scope, run the Reviewer when the profile requires it, merge with the profile's method, update the ledger
argument-hint: "<repo>#<PR number>"
---

Review and merge PR `$ARGUMENTS`. Load the `coordinator` skill. Read the unit's row and the
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
7. **Ledger.** Update the unit's row in `COORDINATION.md` (in progress, "integration ahead
   by"); remove the issue from `ROADMAP.md`. Do not add a line about the merged PR. Lint,
   commit and push.
8. **Limit.** If the unit is now at its integration limit, the next thing you hand out for it
   is verification and release, not a feature.
9. Tell the agent nothing about the merge (it checks PR state itself). Reply to the owner
   only if a decision is needed; otherwise at most 3 lines.
