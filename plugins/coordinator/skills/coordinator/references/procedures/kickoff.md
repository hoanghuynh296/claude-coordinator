# Procedure: Start a new project

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

You are now the coordinator for a new project.
Input (optional): the repo `owner/name` and the local folder, from the command arguments or from what the owner said.

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
  topology, units with session mode, gate, release authority and release rule (groups, ceiling), optional
  roles (only those whose trigger is true), flow, contracts, review rules, packs, budgets,
  owner rules. Start from the closest starting point in `references/profile.md` and adjust.

## Step 3 - STOP for approval
Show the summary: units and how they are staffed, the flow, who releases what, the first
stretch, owner-side tasks, and the paths of both drafts. **Create nothing until the owner
approves in a later message.**

## Step 4 - create (after approval)
- Ledger: `bash "<plugin>/scripts/init-ledger.sh" <ledger-dir> --name "<Project>" --owner <github-user>`,
  then replace `coordination/PROFILE.md` with the approved profile and fill `ROADMAP.md`,
  `README.md` and `COORDINATION.md`. Create the private ledger repo on GitHub and push.
  `multi-repo`: the ledger dir is the workspace root; add a `.gitignore` that ignores
  everything except `COORDINATION.md` and `coordination/`.
- Repos: create what the profile lists. For the single-repo SaaS starting point,
  `bash "<plugin>/scripts/bootstrap.sh" <owner/repo> <local-dir> --values <file> --plan <PLAN.md>`
  builds the repo from the template repo `hoanghuynh296/agent-project-template` (private: it needs access to
  that repo, or pass `--template <your own template repo>`; run it with `--dry-run` first).
  For other shapes create the repos with `gh repo create`, add the integration branch, and
  give each unit an `AGENTS.md`.
- Guards: `bash "<plugin>/scripts/install-guards.sh" --settings <unit-dir>...`
  (pre-push guard, delete-branch-on-merge). Releases follow one standard: `release/vX.Y.Z`
  from `develop` → PR into `main` → tag → back-merge `main` into `develop`, so `develop` is
  never a PR head and delete-branch-on-merge cannot remove it. The coordinator names its own
  branches `release/vX.Y.Z`, `backmerge/vX.Y.Z` or `coordinator/<topic>` (the Next guard skips them).
- Labels: `task`, plus `unit:<unit>` in a single-repo project.

## Step 5 - register and report
Follow the `coordinator-register` procedure (ledger dir, unit dirs), then the `audit` procedure.
Registration reads the app settings (`mcp__ccd_settings__get_settings`): if
`auto_archive_on_pr_close` is on, ask the owner to turn it off before any agent starts, and
record the result in `PROFILE.md` ("Flow").
Commit and push the ledger. Send the owner one message: what exists now, the owner-side task
list, and the first issues you propose to hand out.
