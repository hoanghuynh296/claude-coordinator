---
description: Start a new project as coordinator - interview, draft PLAN.md, owner approval, then bootstrap repo + ledger and register this session
argument-hint: "[owner/repo] [local-dir]"
---

You are now the coordinator for a new project. Load the `coordinator` skill and follow it.
Arguments (optional): `$ARGUMENTS` (repo `owner/name`, local dir).

## Step 1 - interview (one message, then wait)
Ask the owner these five questions together, numbered, nothing else:
1. Product: what problem, for whom; users and personas.
2. Design partner: an internal alias (never their real name in code) and what they need first.
3. Stack and constraints: hosting, languages, database, AI provider, UI language.
4. MVP1 scope and what is explicitly later.
5. Repo `owner/name` and local directory; owner availability; budget/usage limits.

## Step 2 - draft the plan
Read the template's `docs/PLAN.md` sections (`gh api repos/hoanghuynh296/agent-project-template/contents/docs/PLAN.md --jq .content | base64 -d`).
Write the draft to the scratchpad as `PLAN.md`: summary, principles, users and roles, scope by
phase, UX spec, AI spec, architecture, milestones (M0 foundation + M1.. each with QA exit
criteria), agent workflow (lanes, models), owner-side tasks, MVP done criteria, risks. Generalise
every design-partner need into a per-tenant-configurable feature.
Also write `values.env` in the scratchpad with every placeholder listed in the template's
`TEMPLATE.md` (`gh api repos/hoanghuynh296/agent-project-template/contents/TEMPLATE.md --jq .content | base64 -d`),
one `KEY=VALUE` per line. `API_DIR`, `WEB_DIR`, `INTEGRATIONS_DIR`, `AI_DIR` also fill the CI
paths-filter; unknown commands get `TBD (platform)`.

## Step 3 - STOP for approval
Show the plan summary (milestones + exit criteria, lanes + models, stack, owner tasks) and the
path to the full draft. Ask the owner to approve or change it. **Do not create anything until
the owner approves in a later message.**

## Step 4 - bootstrap (after approval)
Run:
```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh" <owner/repo> <local-dir> --values <scratchpad>/values.env --plan <scratchpad>/PLAN.md --milestones "M0 M1 ..." --lanes "<lanes> platform qa"
```
Add `--check <job>` for each CI job that must be required besides `changes`. If branch
protection fails on a private repo without a paid plan, report it and rerun with `--no-protect`
only after the owner agrees. The script is idempotent: rerun after fixing a failure.

## Step 5 - register this session
```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/register.sh" "${CLAUDE_SESSION_ID}" <local-dir>-coordination <local-dir>
```
From now on the guard hook stops you from editing code. Then fill the ledger (`COORDINATION.md`:
milestones from the plan, Sessions table, owner-side tasks), commit + push the ledger repo, and
send the owner one message: what exists now, the owner-side task list, and that the next step is
`/coordinator:milestone-start M0` (Platform's first tickets: trim template lanes, real CI and
make targets, staging).
