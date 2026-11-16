---
description: Create one task as a GitHub issue (goal, acceptance criteria, checks, scope, dependencies) and add it to the unit's backlog in ROADMAP.md
argument-hint: "<unit> <short goal>"
---

Create one task issue for: `$ARGUMENTS`. Load the `coordinator` skill.

1. From `coordination/PROFILE.md` take the unit's repo, what it owns and its gate. If the goal
   needs two units, write two issues and link them. If it changes a contract between units,
   the contract issue comes first and the others say "depends on #<n>".
2. Write the body from `references/templates/task-issue.md` into a scratchpad file: goal,
   acceptance criteria as observable outcomes, the checks that prove it (the unit's gate plus
   anything specific), scope in and out, dependencies, notes. Write for a reader who has not
   seen this conversation.
3. Check the unit's integration limit (`COORDINATION.md` "Integration ahead by" against the
   profile). At the limit, only verification, fix, test and docs issues may be handed out; a
   feature issue is still created but placed after the release item in `ROADMAP.md`.
4. Create it:
   `gh issue create --repo <repo> --title "<title>" --label task --body-file <file>`
   (add `--label unit:<unit>` in a single-repo project, and `--milestone <Mn>` when the cadence
   uses milestones).
5. Add `<owner/repo>#<n> <title>` at the right position of the unit's list in
   `coordination/ROADMAP.md`. Anything it needs from the owner also goes into the owner queue
   in `COORDINATION.md`. Lint, commit and push the ledger.
6. Reply with the issue link only. Hand it to the agent in your next batched message to that
   unit, not as a separate ping.
