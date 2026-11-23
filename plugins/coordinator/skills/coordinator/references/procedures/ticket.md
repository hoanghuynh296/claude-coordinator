# Procedure: Write one task issue

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Create one task issue for the unit and goal that were given.

1. From `coordination/PROFILE.md` take the unit's repo, what it owns and its gate. If the goal
   needs two units, write two issues and link them. If it changes a contract between units,
   the contract issue comes first and the others say "depends on #<n>".
2. Write the body from `references/templates/task-issue.md` into a scratchpad file: goal,
   acceptance criteria as observable outcomes, the checks that prove it (the unit's gate plus
   anything specific), scope in and out, dependencies, notes. Write for a reader who has not
   seen this conversation.
3. **Group and size.** Place the issue in a release group of the unit in `ROADMAP.md`, or start
   a new group (name, target version). Size it: **large** (changes UI or an API, a breaking or
   visible change for apps, or apps must act) is its own group, never mixed into another;
   **small** (fix, docs, internal refactor, additive) rides with the open group it belongs to
   or a patch batch group; an **urgent** fix (broken build in an app, security, data loss,
   production regression) goes first and is released as a patch at once. Then check the
   safety ceiling (`COORDINATION.md` "Integration ahead by" against the profile's "Release"
   column; default 2 weeks or 15 PRs). Past it, only verification, fix, test, docs and
   group-completing issues may be handed out; a new feature issue is still created, in its
   own group after the release item.
4. Create it:
   `gh issue create --repo <repo> --title "<title>" --label task --body-file <file>`
   (add `--label unit:<unit>` in a single-repo project, and `--milestone <Mn>` when the cadence
   uses milestones).
5. Add `<owner/repo>#<n> <title>` under its group, at the right position, in
   `coordination/ROADMAP.md`. Anything it needs from the owner also goes into the owner queue
   in `COORDINATION.md`. Lint, commit and push the ledger.
6. Reply with the issue link only. Hand it to the agent in your next batched message to that
   unit, not as a separate ping.
