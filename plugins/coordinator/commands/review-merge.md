---
description: Review and merge a lane PR - check CI and scope, run the Reviewer when required, merge into develop, update the ledger
argument-hint: "<PR number>"
---

Review and merge PR `$ARGUMENTS`. Load the `coordinator` skill.

1. `gh pr view <n> --json title,baseRefName,headRefName,mergeable,statusCheckRollup,files,additions,deletions,closingIssuesReferences,body`.
   - Not green -> tell the lane (batched), stop. Lanes own their PR to green.
   - Base is not `develop` (stacked PR) -> `gh pr edit <n> --base develop` before merging anything
     under it, or its commits are lost.
   - Files outside the ticket's allowed paths or the lane's ownership -> send back.
2. Decide the Reviewer. **Mandatory** if the diff touches auth, sessions, permissions, tenancy /
   tenant scoping, money/billing/payments, AI tools that write data, secrets or crypto; or if it
   is large (> ~400 changed lines or > 15 files). Otherwise skim the diff yourself against
   `references/review-checklist.md` (summary only; do not load whole files into your context).
3. Reviewer: spawn `coordinator:reviewer` with the PR number, repo, ticket link and the risk area.
   It returns a verdict + ranked findings in at most 15 lines.
   - Blocking findings -> one batched message to the lane with the findings; stop until it
     reports green again.
   - Non-blocking -> add to the ledger follow-ups (or a new ticket).
4. Merge: `gh pr merge <n> --squash --delete-branch` (into `develop`).
5. Ledger: set the row to `merged`, note reviewer verdict and follow-ups; commit + push the ledger.
6. If the merge touches an exit criterion, include "run acceptance on develop" in your next
   batched message to QA. If it unblocks a waiting ticket (e.g. the contract), hand that ticket out.
7. Reply to the owner only if a decision is needed; otherwise at most 3 lines.
