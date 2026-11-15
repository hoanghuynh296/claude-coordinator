# Pitfalls (learned the hard way)

1. **Shared-file conflicts.** Several tickets each touched CI, Makefile or AGENTS.md; every
   merge conflicted. -> Platform is the sole owner of shared/root files; other tickets request
   changes through it.
2. **`ubuntu-latest` moved** and broke a pinned Playwright. -> Pin runner images
   (`ubuntu-24.04`) and tool versions.
3. **paths-filter needs `pull-requests: read`** in the workflow permissions, or it fails on PRs.
4. **CI green has no wake-up.** The coordinator never learned a PR went green. -> Lanes own
   their PR to green with Auto-fix and report "ready + green" once.
5. **Coordinator doing git plumbing** (pushing, opening PRs, cleaning worktrees for subagents)
   bloated its context. -> Agents push, open PRs and clean their worktrees themselves.
6. **Stacked PRs merged into their base lose work.** When the base PR merged (and its branch
   was deleted), the child PR's commits went nowhere. -> Retarget stacked PRs to `develop`
   before merging the base.
7. **Memory-only rules get violated.** "The coordinator never edits code" was broken under
   pressure. -> Hook enforcement (the guard in this plugin).
8. **Reviewer catches what tests miss.** It found 2 high-severity auth bugs that CI and the
   author's 53 tests missed. -> Reviewer is mandatory for auth, tenancy, money, AI write PRs.
9. **Sessions cannot be started from Remote Control** and only from the owner's own message in
   the desktop app. -> Start all milestone sessions in one owner turn; when the owner is remote,
   fall back to background subagents with the same brief and worktree isolation (they push and
   open PRs), and convert them to lane sessions when the owner is back at the desktop.
10. **Usage limits stop every agent at once.** -> Keep the ledger current at all times; after the
    reset resume each agent with SendMessage instead of starting new ones (new ones start cold
    and duplicate work).
11. **Unpushed worktrees get cleaned up.** An isolated worktree with no commits was auto-cleaned
    during a usage-limit pause and all its work was lost. -> Every brief: commit after each step,
    push the branch right after the first commit, then after every commit.
12. **Release tags only from `release/*`.** The template's release workflow tags `v$(cat VERSION)`
    only for PRs from `release/*` branches into main. A PR from `develop` straight to main merges
    without a tag.
13. **Template placeholders left behind.** `{{API_DIR}}` etc. also live in
    `.github/workflows/ci.yml`; unfilled, CI filters match nothing. The bootstrap script fails if
    any placeholder remains and deletes `TEMPLATE.md` only after all are filled.
14. **Branch protection on private repos** needs a paid GitHub plan; bootstrap fails loudly. Use
    `--no-protect` and tell the owner, or make the repo public.
