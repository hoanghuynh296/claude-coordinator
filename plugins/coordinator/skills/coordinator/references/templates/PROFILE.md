# {{PROJECT_NAME}}: project profile

How this project applies the coordinator kit's core principles. This is the only place where
the project's working rules are written; other files point here. Change it when a rule
changes, and log the change in `DECISIONS.md`.

Last reviewed: {{DATE}}

## 1. Topology

<single-repo | multi-repo | hybrid>. <One line: why.>

## 2. Units

| Unit | Repo / path | Owns | Model, effort | Session | Gate (must be green to merge) | Released by | Release |
|---|---|---|---|---|---|---|---|
| <name> | <owner/repo or dir/**> | <what> | <model>, <effort> | <standing or per-issue> | <CI check that must be green, e.g. CI `tests` green; manual check if any> | <owner or coordinator> | <by feature group; ceiling 2 weeks or 15 PRs> |

Release: by feature group (large = its own group, released whole with migration notes; small
= rides with the open group or a patch batch; urgent fix = patch at once). The ceiling is a
safety net only: past it, no new feature work in that unit until the group is split or done.

Tools (what each unit's agents keep; every other optional group of `scripts/agent-tools.json`
is off, written by `install-guards.sh --tools "<groups>"` into the unit repo's committed
`.claude/settings.json`): <unit>: <none | browser semi-design | ios-simulator | ...>.

Agent session names: "Agent: <unit>" (per-issue: "Agent: <unit> #<issue>").
Every session sits at the top level of the sidebar, each agent in its own worktree: whoever
starts a session detaches it right away. Agents report by message to "Coordinator:
{{PROJECT_NAME}}" (PR ready, blocked or decision needed, handover written), each report
ending `Context: <k tokens>`. "PR ready" goes out on push (the first line of the report starts with `PR ready:`), once the local gate (lint and
tests) is green, with the head SHA and the CI state then (pending, green or red); agents never
wait for CI. On every "PR ready" the coordinator starts a background CI watch
(`scripts/ci-watch.sh`) and reviews in parallel; it merges only when CI is green on the
reported head and the review passed. One issue, one full lifecycle: after "PR ready" the
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
- Same-session next issue (`per-issue` units): `PR #<n> merged. Next: #<m> (same session)`, only
  if `#m` is in the same unit, the agent's measured context is under the same-session cap
  (section 8), no session can be started this turn (Remote Control, an automated turn, a refused
  start), `#m` is not in a Reviewer-mandatory risk area, and the session has done fewer than 3
  issues in a row; otherwise a fresh session.
- App setting `auto_archive_on_pr_close`: off (checked <date>). With it on, the app archives
  every session bound to a PR when that PR closes, the coordinator included.
- A release is: <release PR into main | tag | published package | data release>, per unit if they differ.
  With a `develop`: branch `release/vX.Y.Z` from `develop` → PR into `main` → tag → back-merge
  `main` into `develop`; `develop` is never a PR head, so delete-branch-on-merge is safe.
  Tag-only repo (no `develop`): delete the line above and write "released by tag on `main`; no release PR, no back-merge".
- Cadence: <milestone | continuous>.
- Hotfix: <branch from the release branch, PR into it, then back-merge>.

## 5. Contracts between units

| Producer → consumer | Artifact | Pinned in | Checked by |
|---|---|---|---|
| <unit → unit> | <schema, package, data release> | <file> | <test or CI job> |

<Delete this section if there is one unit.>

## 6. Review

- Reviewer mandatory for: <risk areas, e.g. auth, money, contract or lock changes, hardware control>.
- Reviewer mandatory above: 400 changed lines or 25 hand-written files <defaults>. Not counted:
  `CHANGELOG.md`, `VERSION`, `package*.json`, lockfiles, `public/**` mirrors, `**/vendor/**`
  <, plus: ...>. A release PR is exempt when every feature PR in it passed review.
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
- Coordinator: soft <300k>, hard <450k>, on any model and window (`check-context.sh --coordinator`).
- <Agents per model, if they differ. A small window caps an agent's soft at 50% and hard at 75%
  of it: a 200k window gives soft 100k, hard 150k.>
- Same-session cap (`per-issue` units): <175k>. A same-session next issue only under it.
- Reports: at most <6> lines. Reviewer: at most 15 lines.
- `COORDINATION.md`: at most <80> lines.
- No ack-only or status-ping messages. One batched message per agent per round. The merge
  notice `PR #<n> merged. Next: ...` is not a ping: it is the only thing that starts an
  agent's next step.

## 9. Deploy

- Where prod runs: <host / platform / URL>; which checkout and branch is deployed: <repo, branch>.
- Who deploys: <owner | a named ops agent | CI>. The coordinator never deploys.
- Deploy-only items that no gate can check (a prod migration, a real device, a live webhook) are
  merged as `UNVERIFIED: <what>` and kept as their own debt class "Deploy-only" in
  `ROADMAP.md` "Verification debt", cleared by whoever deploys.

<Delete this section if nothing is deployed.>

## 10. Files with no unit

Root and tooling files that belong to no unit: <.claude/**, .vscode/**, README.md, OWNERSHIP.md, ...>.
Owner of each: <unit | the coordinator | the owner>. A change to them goes through an issue for
that owner, like any other file.

## 11. Owner rules

- Language: <the owner is addressed in ...; agents, code and docs use ...>.
- Spending: anything that costs money needs the owner's approval first, with its price.
- Only the owner decides: <releases of ..., secrets, going public, ...>.
- <Other standing rules, each once.>
