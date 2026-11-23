# Procedure: Report status

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Give the owner a status in at most 10 lines.

1. Read `COORDINATION.md` and the units table of `coordination/PROFILE.md`.
2. GitHub, compact queries only, per unit repo:
   `gh pr list --repo <repo> --json number,title,baseRefName,statusCheckRollup --jq '.[] | [.number,.baseRefName,.title,([.statusCheckRollup[]?.conclusion]|unique|join(","))] | @tsv'`
   and `gh issue list --repo <repo> --label task --state open --json number,title --jq '.[] | [.number,.title] | @tsv'`.
3. Contexts of the agent sessions (session tools, or `scripts/check-context.sh`).
4. Output, decisions first: what the owner must decide or do; then per unit one line
   (released, integration ahead by against its ceiling and its open release group, in progress, blocked on); PRs waiting
   for review; sessions at `SOFT` or `HARD`; verification debt count.
5. If the ledger disagrees with GitHub, fix the ledger, lint, commit and push.
