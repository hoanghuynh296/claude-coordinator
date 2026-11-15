# {{PROJECT_NAME}} - Coordination ledger

Project repo: `{{REPO}}` · Ledger repo: `{{LEDGER_REPO}}` (private) · Owner: {{OWNER_GITHUB}} · Started: {{DATE}}

The coordinator keeps this file current and commits + pushes it after every merge, decision or
session change. If the coordinator session dies (usage limit, crash, rotation), this file plus the
newest note in `handover/` must be enough to continue.

## 1. Roles

| Role | Who | Model | Owns |
|---|---|---|---|
| Owner | {{OWNER_GITHUB}} | human | approves plan, real decisions, non-code tasks, demo tests, merges release PRs |
| Coordinator | session "Coordinator" | Opus | this ledger, docs/PLAN.md, docs/adr/, tickets, review, merges into develop, releases |
| Platform | session "Agent: platform" | Sonnet | CI, Makefile, workspace/root files, compose, infra, staging, deploy, observability, branch protection |
| QA | session "Agent: qa-M<n>" | Sonnet | e2e/, fixtures/, evals/, acceptance per milestone |
| Reviewer | subagent `coordinator:reviewer` | Opus | read-only review of large/sensitive PRs |
| Lane | session "Agent: <lane>" | per lane | directories in OWNERSHIP.md |

## 2. Workflow (short)

ticket (Issue) -> lane branch `t<m>.<n>-<slug>` -> PR `Closes #N` -> lane fixes CI with Auto-fix ->
lane reports "ready + green" -> Reviewer if large/sensitive (mandatory for auth, tenancy, money,
AI write tools) -> coordinator merges into develop -> ledger update (commit + push) -> QA on
develop/staging -> milestone close: QA green on staging, owner demo, release PR `release/*` -> main, tag.

## 3. Token rules

- No ack-only or status-ping messages. One batched message per agent per round.
- Lanes report only "PR ready + CI green" or "blocked/decision", at most 6 lines.
- Rotate any session at ~250k context: handover note in `handover/`, fresh session, same name.
- Coordinator measures contexts on each owner message (`scripts/check-context.sh`).
- After a usage-limit stop: resume each agent with SendMessage; do not start new ones.

## 4. Sessions

| Name | Kind (session/subagent) | Model | Worktree / branch | Current ticket | Context | Last handover |
|---|---|---|---|---|---|---|
| Coordinator | session | Opus | - | - | | |

## 5. Milestones

### M0 - Foundation

Exit criteria: (from docs/PLAN.md section 7)

| # | Ticket | Lane | Issue | PR | Status | Reviewer | Notes |
|---|---|---|---|---|---|---|---|
| T0.1 | | platform | | | todo | | |

Status values: todo, in-progress, pr-open, green, reviewed, merged, blocked.

QA: suite `e2e/m0/` · last run: - · staging: -

## 6. Decisions

| ID | Date | Decision | Why | Asked owner? |
|---|---|---|---|---|
| C-001 | {{DATE}} | | | |

Architecture decisions with long-term impact also get an ADR in the project repo `docs/adr/`.

## 7. Owner-side tasks

| # | Task | Needed by | Status |
|---|---|---|---|
| O-1 | | | todo |

## 8. Follow-ups

- [ ] (findings deferred from reviews, tech debt, ideas; each one becomes a ticket or is dropped)
