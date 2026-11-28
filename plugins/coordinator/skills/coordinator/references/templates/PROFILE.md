# {{PROJECT_NAME}}: project profile

How this project applies the coordinator kit's core principles. This is the only place where
the project's working rules are written; other files point here. Change it when a rule
changes, and log the change in `DECISIONS.md`.

Last reviewed: {{DATE}}

## 1. Topology

<single-repo | multi-repo | hybrid>. <One line: why.>

## 2. Units

| Unit | Repo / path | Owns | Model per runtime | Session | Gate (must be green to merge) | Released by | Release |
|---|---|---|---|---|---|---|---|
| <name> | <owner/repo or dir/**> | <what> | Claude: <model>, <effort>; Antigravity: <model> | <standing or per-issue> | <CI check that must be green, e.g. CI `tests` green; manual check if any> | <owner or coordinator> | <by feature group; ceiling 2 weeks or 15 PRs> |

Model per runtime: each runtime names its own model (Antigravity runs no `claude-*` model);
write "Antigravity: not used" when the unit never runs there.

Release: by feature group (large = its own group, released whole with migration notes; small
= rides with the open group or a patch batch; urgent fix = patch at once). The ceiling is a
safety net only: past it, no new feature work in that unit until the group is split or done.

Tools (what each unit's agents keep; every other optional group of `scripts/agent-tools.json`
is off, written by `install-guards.sh --tools "<groups>"` into the unit repo's committed
`.claude/settings.json` and `.claude/lean-tools.lock.json`): <unit>: <none | browser semi-design | ios-simulator | ...>.

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
| Coordinator | yes | session "Coordinator: {{PROJECT_NAME}}", Claude: <model>; Antigravity: <model> |
| Platform | <yes or no> | <unit and what it owns, or why not needed> |
| QA | <yes or no> | <per milestone, or why not needed> |
| Reviewer | yes | subagent `coordinator:reviewer`; mandatory for the risk areas in section 6 |
| One-off builder | yes | subagent `coordinator:oneoff-builder` per the kit's delegation split (`references/sessions.md`): self-contained one-round work outside the risk areas; every brief while sessions cannot be started |

## 4. Flow

- Integration branch: `<develop>`. Release branch: `<main>`. Merge method: <merge commit or squash>.
- Owner approves merges into: none.
  (Kit default `none`: the coordinator merges every PR on green CI and a passed review, and
  the owner approves releases only. Name branches, `main, develop`, only when the owner wants
  to approve each merge into them; `merge-pr.sh` then refuses those without `--owner-approved`.)
  After merging a `per-issue` agent's PR, the coordinator archives that agent's session; a
  `standing` session is archived only on rotation.
- Same-session next issue (`per-issue` units): only under the kit's strict rule
  (`references/procedures/review-merge.md` step 9), with the cap of section 8.
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
- Coordinator: soft <300k>, hard <450k>, on any model and window (`check-context.sh --profile
  <ledger>` reads this section; a `Coordinator: …` session or `--role coordinator` gets these).
- <Agents per model, if they differ. A small window caps an agent's soft at 50% and hard at 75%
  of it: a 200k window gives soft 100k, hard 150k.>
- Same-session cap (`per-issue` units): <175k>. A same-session next issue only under it.
- Delegation: <the kit's default split | <unit>: sessions only | <unit>: subagent for <kinds>>.
- Reports: at most <6> lines. Reviewer: at most 15 lines.
- `COORDINATION.md`: at most <80> lines.
- No ack-only or status-ping messages. One batched message per agent per round. The merge
  notice is not a ping: it is the only thing that starts an agent's next step.
- Token economy (`references/token-economy.md`; measured with the token audit):
  - Models per task type: <strong model> for behaviour, layout, contracts; <cheaper model> for
    re-reviews of small fix commits, release bumps, generated docs, codemods, probes.
  - Local gate per issue: <fast gate command> plus the tests of what changed
    (<how to run one spec>); the full suite is CI's job.
  - Known (copied into every brief): <flaky tests and how to treat them>, <tool limits>,
    <ports>, <accounts>.
  - Token audit: at every release or milestone close.

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
