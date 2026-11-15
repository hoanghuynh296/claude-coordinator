---
description: Concise milestone status from the ledger and GitHub (tickets, PRs, CI, QA, sessions, owner decisions)
---

Give the owner a status in at most 10 lines. Load the `coordinator` skill.

1. Read `COORDINATION.md` (current milestone table, Sessions, owner tasks, decisions).
2. GitHub, compact queries only:
   `gh pr list --repo <repo> --base develop --json number,title,headRefName,statusCheckRollup --jq '.[] | [.number,.title,([.statusCheckRollup[]?.conclusion]|unique|join(","))] | @tsv'`
   and `gh issue list --repo <repo> --milestone <Mn> --state open --json number,title,labels --jq '.[] | [.number,.title] | @tsv'`.
3. Contexts: `"${CLAUDE_PLUGIN_ROOT}/scripts/check-context.sh" <session ids>`.
4. Output: milestone + progress (merged/total), PRs waiting (green / red / in review), QA state,
   blocked items with owner, sessions near rotation, decisions needed from the owner (first).
   If the ledger disagrees with GitHub, fix the ledger and push it.
