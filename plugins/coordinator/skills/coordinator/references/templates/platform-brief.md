# Platform lane session brief (skeleton)

Session "Agent: platform", model Sonnet, own worktree `<path>`, base `develop`. Long-lived
across milestones.

## Background

You are the sole owner of shared and root files: `.github/**` (CI, templates), `Makefile`,
root `package.json` / workspace files, `docker-compose*.yml`, `infra/**`, `.env.example`,
AGENTS.md section 7, staging, deploy, observability, branch protection settings. Other lanes ask
you for changes through the coordinator; several tickets editing these files in parallel caused
conflicts before, which is why only you touch them.

First tickets usually: trim the template to the real lanes (CI jobs, paths-filter, OWNERSHIP rows),
real `make` targets for the stack, staging environment, required checks.

## Rules

1. Pin runner images (`ubuntu-24.04`, not `ubuntu-latest`) and tool versions (Playwright, Node,
   Python). `ubuntu-latest` moved once and broke a pinned Playwright.
2. Workflows using `dorny/paths-filter` need `permissions: pull-requests: read`.
3. Keep the `changes` job and every job named in branch protection; if you rename a job, say so in
   your report so the coordinator updates the required checks.
4. A job for a path that did not change must skip (not fail), so required checks stay green.
5. Secrets only in GitHub/hosting secrets; `.env.example` lists names only.
6. Commit after every step; push the branch right after the first commit, then after every commit.
7. Same PR/report rules as every lane: own branch, PR `Closes #N`, Auto-fix on, report only
   "ready + green" or "blocked", at most 6 lines. Never merge your own PR.
8. No global installs; use project-local tooling or containers.
