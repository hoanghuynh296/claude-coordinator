# The project profile

`coordination/PROFILE.md` in the ledger repo records how *this* project applies the core
principles. It is the only place where the project's working rules are written. Commands and
briefs read it; they do not assume a shape.

Write it at kickoff or adoption (template: `templates/PROFILE.md`). Change it when the owner
changes a rule, in the same turn, and log the change in `DECISIONS.md`.

## The choices

### 1. Topology: what a unit is

| Topology | A unit is | Use when |
|---|---|---|
| `single-repo` | a lane: a set of directories in one repo, each agent in its own worktree | one product, one deployable, the parts share a build |
| `multi-repo` | a whole repo, cloned side by side under one workspace folder | parts have different licences, release cycles or consumers; they meet at published artifacts |
| `hybrid` | either, per unit | a multi-repo project where one large repo also needs lanes |

One unit is fine. A project with a single repo and a single agent still gains from the ledger,
issues and independent review.

### 2. Units

For each unit: name, repo and path, what it owns, model and effort, session mode, its
verification gate, who may release it, and its integration limit.

**Session mode**

| Mode | What it means | Use when |
|---|---|---|
| `standing` | one long-lived session "Agent: <unit>", rotated past the soft context threshold (after its current issue) with a handover note | the unit has a steady queue and work in flight carries context (a long build, a multi-PR feature) |
| `per-issue` | a fresh session for each issue, archived by the coordinator after its PR merges (unless the coordinator sends a same-session Next, below); no handover notes | work is intermittent or each task is self-contained; the unit's docs are good enough to start cold |

A `per-issue` session may take the next issue of its unit in the same session only when the
coordinator sends `PR #<n> merged. Next: #<m> (same session)`, which it does only if `#m` is in
the same unit, the agent's context (measured, not self-reported) is under 50% of the unit's soft
threshold, `#m` is not in a Reviewer-mandatory risk area, and the session has done fewer than 3
issues in a row. Otherwise it gets `Next: done` and the next issue starts fresh. The session
stays `per-issue`: it never becomes `standing` by repetition.

`per-issue` only works if the unit's `AGENTS.md` and docs carry everything a cold start needs.
If a per-issue agent keeps asking the same questions, fix the docs, not the mode.

In either mode an agent works one issue at a time through its full lifecycle: PR pushed,
local gate green, "PR ready" (head SHA, CI state, ending `Context: <k tokens>`; never waiting
for CI), review and CI fixes, then it waits for the coordinator's
`PR #<n> merged. Next: <issue | handover | stand by | done>`. Never hand out a queue. The
coordinator owns the CI wait: a background `scripts/ci-watch.sh` per "PR ready".

In either mode every session sits at the top level of the sidebar: whoever starts it detaches
it right away, and it reports by message to "Coordinator: <project>". This is not a profile
choice; nested sessions are archived with their parent and lose their reports at rotation.

**Gate.** The command (or CI job) that must be green before a PR may merge, plus any manual
check that CI cannot do (for example a browser pass for UI). Write the exact command. Name
the local part (lint and tests the agent runs before "PR ready") and the CI job the
coordinator watches before merging; they may be the same checks.

**Release authority.** `owner` or `coordinator`, per unit. Typical: the owner releases what
users see; the coordinator releases libraries, data and internal tools.

**Integration limit.** How far the integration branch may run ahead of the last release before
feature work stops (principle 6). For example "15 PRs or 5 days". Set it from how much the
releaser can verify in one sitting.

### 3. Roles (optional ones)

None is mandatory. Add a role when its trigger is true; remove it when it stops paying.

| Role | Add it when |
|---|---|
| Platform (sole owner of shared and root files: CI, build files, infra) | several units edit the same root files and their PRs conflict |
| QA (acceptance tests from exit criteria, verdict on staging) | the product has user-facing flows, a staging environment, and milestones with exit criteria |
| Reviewer (independent, read-only subagent) | always available; the profile lists the risk areas and size limits that make it mandatory |
| One-off builder (subagent with its own branch and PR) | small self-contained tasks outside any unit's queue, or when sessions cannot be started |

### 4. Flow

- **Branches:** the integration branch (for example `develop`), the release branch (`main`),
  the merge method (merge commit or squash), and what a release is (a release PR, a tag, a
  published package, a data release).
- **Cadence:** `milestone` (work is planned in milestones with exit criteria and closed with a
  demo) or `continuous` (an ordered backlog per unit; release when the gate and the owner say
  so). A project may use milestones for one unit and a continuous backlog for another.

### 5. Contracts between units

Where units meet: the artifact (schema, package, data release), where its version is pinned, and
the test or CI job that checks it (see `packs/artifact-contracts.md`). Omit with one unit.

### 6. Review rules

- Risk areas where the Reviewer is mandatory. Typical: auth, permissions, money, data
  deletion, tenancy, secrets, contract changes, anything that controls hardware.
- Size limits above which the Reviewer is mandatory.
- Which checklists apply: always `review-checklist.md`, plus the packs the project uses.

### 7. Coordinator edit policy

What the coordinator session may edit outside the ledger (the guard hook enforces it). The
default is planning files only. In a very small project the owner may let the coordinator
write code; then say so in the profile and register without the guard.

### 8. Budgets

Context thresholds for rotation, report length, model per role, ledger size budget. Defaults:
soft 250k, hard 400k (or 75% of the model's context window, whichever is lower), reports in 6
lines, `COORDINATION.md` at most 80 lines. Thresholds may differ per model. For a small
window, soft is capped at 50% and hard at 75% of it (a 200k window: soft 100k, hard 150k).

- **Soft:** do not stop mid-task. The session finishes its current issue (PR, gate green),
  takes no new one, writes its handover, and is replaced after that PR. The coordinator sends
  it no new issues.
- **Hard:** the session stops at the next safe point (commit, push), writes a full handover
  (done, left in order, decisions, commands to re-run, traps) and reports "blocked: rotate".
- Why two: one threshold that stops a session mid-task makes the fresh session re-read
  everything, which costs more than it saves. The hard one is the safety margin.

`check-context.sh --soft <n> --hard <n> [--window <n>]` reports `ok`, `SOFT` or `HARD`. One
run applies one set of thresholds: run it once per model group when they differ.

### 9. Deploy

Where prod runs, which checkout and branch is deployed, and who deploys (the coordinator never
does). Deploy-only items no gate can check are merged as `UNVERIFIED` and kept as their own
debt class "Deploy-only" in `ROADMAP.md`, cleared by whoever deploys. Omit if nothing is deployed.

### 10. Files with no unit

Root and tooling files that belong to no unit (`.claude/**`, `.vscode/**`, `README.md`,
`OWNERSHIP.md`): name an owner for each, so a change has an issue and a unit to go to.

### 11. Owner rules

The owner's standing rules, each written once: language, spending approval, what only the
owner decides, how the owner wants to be asked. Machine-specific rules (a work window on one
laptop, a local auth trick) do not go here; they stay in that machine's memory.

## Starting points

Pick the closest one, then adjust. They are examples, not modes.

| Project | Topology | Units and sessions | Optional roles | Cadence | Packs |
|---|---|---|---|---|---|
| SaaS product in one repo | single-repo | lanes (api, web, ...), standing | Platform, QA, Reviewer | milestone | `saas-multitenant`, `ui-product` |
| Family of products that feed each other | multi-repo | one unit per repo; standing where a queue exists, per-issue elsewhere | Reviewer | continuous, releases per unit | `artifact-contracts`, `ui-product` where there is UI |
| One small repo | single-repo | one unit, per-issue | Reviewer | continuous | none |
| Knowledge base or data repo | multi-repo or single | per-issue | Reviewer for generated data and citations | continuous | `artifact-contracts` |
| Library with consumers | single-repo | one or two lanes, standing | Reviewer on public API changes | milestone per version | `artifact-contracts` |

## Changing the profile

A profile is expected to change. Review it when: a unit's agent idles often (switch to
`per-issue`), PRs conflict on shared files (add Platform), a release needs a huge review (lower
the integration limit), the ledger lint keeps failing (the state is in the wrong file), or the
owner adds a rule. Change one thing, log it in `DECISIONS.md`, and tell the affected agents in
their next batched message.
