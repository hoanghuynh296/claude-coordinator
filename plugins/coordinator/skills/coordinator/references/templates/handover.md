# Handover - <session name> - <YYYY-MM-DD HH:MM>

Write this before rotating a session (~250k context) or before a long pause. Save it as
`handover/<YYYY-MM-DD>-<session-slug>.md` in the ledger repo, commit and push. The fresh session
(same name) reads this file first, then COORDINATION.md.

## Role and scope
- Session: "<name>" · role: <coordinator | lane X | platform | qa-Mn> · model: <model>
- Worktree / branch: <path> / <branch>
- Owned paths: <from OWNERSHIP.md>

## State
- Milestone: <Mn> · current ticket(s): #<n> <title>
- Open PRs: #<n> <status: CI green/red, review pending, findings to fix>
- Uncommitted or unpushed work: <none | what and where> (there should be none: commit + push first)

## Next steps (in order)
1.
2.

## Decisions and context the next session needs
- <decision, with C-xxx id if logged>

## Gotchas
- <things that wasted time; commands that work; flaky tests>

## Waiting on
- Owner: <question or task>
- Other lanes: <dependency>
