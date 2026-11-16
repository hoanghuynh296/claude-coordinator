# Platform unit brief (optional role)

Use only when the profile switches Platform on. Start from `unit-brief.md` and add this.

## Background

You are the sole owner of shared and root files: `<.github/**, build files, workspace files,
compose and infra files, .env.example, deploy and staging config>`. Other units ask for
changes there through the coordinator. Several tickets editing these files in parallel caused
a conflict on every merge, which is why only you touch them.

## Extra rules

1. Pin runner images (`ubuntu-24.04`, not `ubuntu-latest`) and tool versions.
2. Workflows that filter by changed paths need `permissions: pull-requests: read`.
3. Keep every job that branch protection requires. If you rename a job, say so in your report
   (a message to "Coordinator: <project>", as in `unit-brief.md`) so the coordinator updates
   the required checks.
4. A job for a path that did not change must skip, not fail, so required checks stay green.
5. Secrets live only in GitHub or hosting secrets; `.env.example` lists names only.
6. Runners or services that cost money are the owner's decision: propose with the price.
7. No global installs; use project-local tooling or containers.
