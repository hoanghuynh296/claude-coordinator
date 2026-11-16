---
description: Concise status from the ledger and GitHub (per unit - released, ahead by, in progress, blocked; owner decisions first)
---

Give the owner a status in at most 10 lines. Load the `coordinator` skill.

1. Read `COORDINATION.md` and the units table of `coordination/PROFILE.md`.
2. GitHub, compact queries only, per unit repo:
   `gh pr list --repo <repo> --json number,title,baseRefName,statusCheckRollup --jq '.[] | [.number,.baseRefName,.title,([.statusCheckRollup[]?.conclusion]|unique|join(","))] | @tsv'`
   and `gh issue list --repo <repo> --label task --state open --json number,title --jq '.[] | [.number,.title] | @tsv'`.
3. Contexts of the agent sessions (session tools, or `scripts/check-context.sh`).
4. Output, decisions first: what the owner must decide or do; then per unit one line
   (released, integration ahead by against its limit, in progress, blocked on); PRs waiting
   for review; sessions near the threshold; verification debt count.
5. If the ledger disagrees with GitHub, fix the ledger, lint, commit and push.
