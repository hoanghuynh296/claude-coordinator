---
description: Close a milestone - QA verdict on staging, demo instructions for the owner, release PR from release/*, tag
argument-hint: "<milestone> [version]"
---

Close milestone `$ARGUMENTS`. Load the `coordinator` skill.

1. Ledger + GitHub: every ticket of the milestone merged or explicitly moved (`gh issue list
   --milestone <Mn> --state open`). Open ones -> list them and stop.
2. QA: ask the QA session (one message) for the final verdict on **staging** per exit criterion.
   Not all green -> list failures with owning lanes, create fix tickets, stop.
3. Demo instructions for the owner (one message): staging URL, test accounts from the project's
   seed/fixture files (never real customer data), 3-6 steps per persona, what to look for, how to
   report problems. Wait for the owner's OK.
4. Release (after OK): ask Platform (or a one-off subagent) to create branch `release/<version>`
   from `develop`, bump `VERSION`, update `CHANGELOG.md`, open PR `release/<version>` -> `main`.
   The branch name must start with `release/`: the release workflow tags `v$(cat VERSION)` only
   for PRs from `release/*`.
5. Tell the owner to merge the release PR (owner merges releases). After merge check the tag:
   `gh release view v<version> --repo <repo>`.
6. If `main` and `develop` diverged, get a back-merge PR `main` -> `develop`.
7. Close the GitHub milestone, update the ledger (milestone closed, follow-ups, decisions),
   commit + push. Measure contexts; rotate sessions near ~250k before the next milestone.
