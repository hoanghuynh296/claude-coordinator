# Roles

| Role | Kind | Model | Does | Never does |
|---|---|---|---|---|
| Owner | human | - | approves the plan, answers real decisions, does non-code tasks (accounts, domains, billing, legal), tests demos, merges release PRs, starts sessions from the desktop app | gets status pings or ack-only messages |
| Coordinator | Claude session | Opus | plan, ADRs, ledger, tickets (GitHub Issues), starts sessions, reviews, merges into `develop`, prepares releases, measures contexts | writes product code, runs setup/infra by hand, does git plumbing for agents |
| Lane | long-lived named session "Agent: <lane>", own worktree | per lane: core backend/AI Opus, web/integrations Sonnet | owns directories per `OWNERSHIP.md`, one branch + PR per ticket, fixes its own CI with Auto-fix | edits other lanes' or shared files, merges its own PR |
| Platform | lane "Agent: platform" | Sonnet | sole owner of shared/root files: CI, Makefile, workspace files, compose, infra, staging, deploy, observability, branch protection | product features |
| QA acceptance | session "Agent: qa-M<n>" per milestone | Sonnet | at milestone start writes E2E acceptance tests from exit criteria; runs them on `develop` with the real stack after merges; persona walkthroughs; final milestone verdict on staging | product code |
| Reviewer | subagent `coordinator:reviewer` | Opus | read-only independent review of large or sensitive PRs with a security checklist; verdict + ranked findings in at most 15 lines | edits, pushes, comments on GitHub |
| One-off | subagent `coordinator:oneoff-builder` (or general) | Sonnet | fixtures, docs, investigations, small fixes; pushes its own branch, opens a PR | long-lived ownership |

## Why these splits

- **Coordinator writes no code.** Its context is the scarcest resource in the project: it holds
  the plan, every ticket and every review. Code, logs and git plumbing fill it fast and force
  early rotation. The guard hook enforces this because a memory-only rule was violated before.
- **Platform owns shared files.** When several tickets each touched CI, Makefile or AGENTS.md,
  their PRs conflicted on every merge. One owner serialises those changes.
- **Lanes own their PR until green.** CI going green gives the coordinator no wake-up signal;
  the lane that watches its own PR with Auto-fix does, and reports once.
- **Reviewer is independent.** The author's tests encode the author's assumptions. The Reviewer
  once caught two high-severity auth bugs that CI and 53 author-written tests missed, so it is
  mandatory for auth, tenancy, money and AI write tools.
- **QA writes tests from exit criteria first.** Acceptance written before the code cannot be
  bent to fit the implementation.

## Models

Opus where mistakes are expensive and reasoning is deep (coordinator, Reviewer, core backend,
AI). Sonnet for well-specified work (web, integrations, Platform, QA, one-offs). Record the
model per session in the ledger's Sessions table.
