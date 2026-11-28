# Handover: <role>, <YYYY-MM-DD>

Write this before replacing a `standing` session or the coordinator, or before a long pause,
and before the session's last PR merges (the coordinator archives a `per-issue` session right
after its PR merges).
Past the soft threshold, after finishing the current issue; past the hard one, at the next safe
point, with every section filled.
Save it as `coordination/handover/<role>.md` in the ledger repo (overwrite the old one; git
keeps history), commit and push. Only what is in flight belongs here. Knowledge about the code
goes into the unit's own docs first; rules go into `PROFILE.md`; state goes into
`COORDINATION.md`.

## In flight
- Issue(s): #<n> <title>
- Open PRs: #<n> <gate green or red, review pending, findings to fix>
- Branches pushed without a PR: <branch: what it holds, what is missing>
- Unpushed work: none <there must be none: commit and push first>
- Background subagents (coordinator only): none <or "running: <agent>, <task>" for each one
  still running; the replacement collects its report>

## Done in this session
- <issue / PR: state>

## Decisions taken
- <what and why, or the DECISIONS.md id>

## Commands to re-run
- <gate, setup, the command that reproduces the open problem>

## Traps
- <what cost time; if it is about the code, it goes into the unit's docs instead>

## Next steps (in order)
1.
2.

## Pending Next (coordinator only)
- <owner/repo#N, from `next-clear.sh <session> --handover`: merged, author not yet sent
  "PR #N merged. Next: ..."> <or "none">

## Waiting on
- Owner: <question or task>
- Other units: <dependency>

## Moved into the unit's docs in this rotation
- <file: what was added> <or "nothing new">
