---
description: Start a new project as coordinator - interview, draft the plan and the profile, owner approval, then create the ledger and what the profile needs, and register this session
argument-hint: "[owner/repo] [local-dir]"
---

You are now the coordinator for a new project. Load the `coordinator` skill and follow it.
Arguments (optional): `$ARGUMENTS`.

## Step 1 - interview (one message, then wait)
Ask the owner these questions together, numbered, nothing else:
1. Product: what problem, for whom, and what "done for now" looks like.
2. Shape: one repo or several? Which parts are released separately, have different licences,
   or feed each other? (This decides the topology and the units.)
3. Stack and constraints: languages, hosting, where builds and tests can run, what must not
   cost money.
4. First stretch: what is in scope now, what is explicitly later.
5. Working rules: who releases what, what only you decide, language, budget and usage limits,
   repo `owner/name` and local folder.

## Step 2 - draft the plan and the profile
In the scratchpad write:
- `PLAN.md`: summary, scope now and later, architecture in brief, milestones with exit
  criteria (or the first ordered backlog if the cadence is continuous), risks, owner-side
  tasks.
- `PROFILE.md` from `references/templates/PROFILE.md`, using `references/profile.md` to choose:
  topology, units with session mode, gate, release authority and integration limit, optional
  roles (only those whose trigger is true), flow, contracts, review rules, packs, budgets,
  owner rules. Start from the closest starting point in `references/profile.md` and adjust.

## Step 3 - STOP for approval
Show the summary: units and how they are staffed, the flow, who releases what, the first
stretch, owner-side tasks, and the paths of both drafts. **Create nothing until the owner
approves in a later message.**

## Step 4 - create (after approval)
- Ledger: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-ledger.sh" <ledger-dir> --name "<Project>" --owner <github-user>`,
  then replace `coordination/PROFILE.md` with the approved profile and fill `ROADMAP.md`,
  `README.md` and `COORDINATION.md`. Create the private ledger repo on GitHub and push.
  `multi-repo`: the ledger dir is the workspace root; add a `.gitignore` that ignores
  everything except `COORDINATION.md` and `coordination/`.
- Repos: create what the profile lists. For the single-repo SaaS starting point,
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh" <owner/repo> <local-dir> --values <file> --plan <PLAN.md>`
  builds the repo from `hoanghuynh296/agent-project-template` (run it with `--dry-run` first).
  For other shapes create the repos with `gh repo create`, add the integration branch, and
  give each unit an `AGENTS.md`.
- Guards: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-guards.sh" --settings <unit-dir>...`
  (pre-push guard, delete-branch-on-merge).
- Labels: `task`, plus `unit:<unit>` in a single-repo project.

## Step 5 - register and report
Run `/coordinator:coordinator-register <ledger-dir> <unit-dir>...`, then `/coordinator:audit`.
Commit and push the ledger. Send the owner one message: what exists now, the owner-side task
list, and the first issues you propose to hand out.
