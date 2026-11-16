# {{PROJECT_NAME}}: project profile

How this project applies the coordinator kit's core principles. This is the only place where
the project's working rules are written; other files point here. Change it when a rule
changes, and log the change in `DECISIONS.md`.

Last reviewed: {{DATE}}

## 1. Topology

<single-repo | multi-repo | hybrid>. <One line: why.>

## 2. Units

| Unit | Repo / path | Owns | Model, effort | Session | Gate (must be green to merge) | Released by | Integration limit |
|---|---|---|---|---|---|---|---|
| <name> | <owner/repo or dir/**> | <what> | <model>, <effort> | <standing or per-issue> | <exact command or CI job; manual check if any> | <owner or coordinator> | <e.g. 15 PRs or 5 days> |

Agent session names: "Agent: <unit>" (per-issue: "Agent: <unit> #<issue>").
Every session sits at the top level of the sidebar, each agent in its own worktree: whoever
starts a session detaches it right away. Agents report by message to "Coordinator:
{{PROJECT_NAME}}" (PR ready and gate green, blocked or decision needed, handover written),
each report ending `Context: <k tokens>`. One issue, one full lifecycle: after "PR ready" the
agent waits; the coordinator hands out one issue at a time and, in the same turn as each
merge, sends the author `PR #<n> merged. Next: <issue | handover | stand by | done>`.

## 3. Roles

| Role | On? | Who / how |
|---|---|---|
| Owner | yes | {{OWNER}} |
| Coordinator | yes | session "Coordinator: {{PROJECT_NAME}}", <model> |
| Platform | <yes or no> | <unit and what it owns, or why not needed> |
| QA | <yes or no> | <per milestone, or why not needed> |
| Reviewer | yes | subagent `coordinator:reviewer`; mandatory for the risk areas in section 6 |
| One-off builder | yes | subagent `coordinator:oneoff-builder` for small tasks outside a unit's queue |

## 4. Flow

- Integration branch: `<develop>`. Release branch: `<main>`. Merge method: <merge commit or squash>.
  After merging a `per-issue` agent's PR, the coordinator archives that agent's session; a
  `standing` session is archived only on rotation.
- App setting `auto_archive_on_pr_close`: off (checked <date>). With it on, the app archives
  every session bound to a PR when that PR closes, the coordinator included.
- A release is: <release PR into main | tag | published package | data release>, per unit if they differ.
- Cadence: <milestone | continuous>.
- Hotfix: <branch from the release branch, PR into it, then back-merge>.

## 5. Contracts between units

| Producer → consumer | Artifact | Pinned in | Checked by |
|---|---|---|---|
| <unit → unit> | <schema, package, data release> | <file> | <test or CI job> |

<Delete this section if there is one unit.>

## 6. Review

- Reviewer mandatory for: <risk areas, e.g. auth, money, contract or lock changes, hardware control>.
- Reviewer mandatory above: <e.g. 400 changed lines or 15 files>.
- Checklists: core + packs <list: saas-multitenant, artifact-contracts, ui-product>.
- Manual checks the gate does not cover: <e.g. browser pass per release by the coordinator>.

## 7. Coordinator edit policy

The coordinator edits the ledger repo and, in the units, only: <e.g. docs/PLAN.md, docs/adr/**>.
Everything else goes through an issue for the owning unit.

## 8. Budgets

- Context, soft: <250k>. Past it a session takes no new issue, finishes the current one (PR,
  gate green), writes its handover before that PR merges, and is replaced.
- Context, hard: <400k, or 75% of the model's context window if lower>. Past it a session
  stops at the next safe point (commit, push), writes a full handover, reports "blocked: rotate".
- <Per model, if they differ: e.g. Opus 1M: soft 400k, hard 700k. A small window caps soft at
  50% and hard at 75% of it: a 200k window gives soft 100k, hard 150k.>
- Reports: at most <6> lines. Reviewer: at most 15 lines.
- `COORDINATION.md`: at most <80> lines.
- No ack-only or status-ping messages. One batched message per agent per round. The merge
  notice `PR #<n> merged. Next: ...` is not a ping: it is the only thing that starts an
  agent's next step.

## 9. Owner rules

- Language: <the owner is addressed in ...; agents, code and docs use ...>.
- Spending: anything that costs money needs the owner's approval first, with its price.
- Only the owner decides: <releases of ..., secrets, going public, ...>.
- <Other standing rules, each once.>
