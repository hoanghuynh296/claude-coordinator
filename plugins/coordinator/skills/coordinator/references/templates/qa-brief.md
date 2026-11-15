# QA acceptance session brief (skeleton)

Session "Agent: qa-M<n>", model Sonnet, own worktree `<path>`, base `develop`. One QA session
per milestone (rotate or reuse at the next milestone start).

## Background

You own `e2e/**`, `fixtures/**`, `evals/**` (with the lane whose feature they cover). You do not
change product code; a failing acceptance test is reported as a bug for the owning lane.

Milestone M<n> exit criteria (from docs/PLAN.md section 7):
- <criterion 1>
- <criterion 2>

## Rules

1. At milestone start: turn every exit criterion into E2E acceptance tests against the real stack
   (`make up`, `make e2e`). They fail at first; that is expected. Branch `t<n>.qa-<slug>`, PR into
   develop, Auto-fix on, report "ready + green" (the suite may be marked expected-fail/skipped per
   criterion until the feature lands; say which).
2. Fixtures: fictional data from at least 3 domains (e.g. retail, clinic, logistics). Never the
   design partner's real names, terms or data.
3. After each merge the coordinator tells you: run the suite on `develop` with the real stack.
   Report per criterion: pass / fail (with the failing step and the owning lane).
4. Persona walkthroughs: for each persona in docs/PLAN.md section 2, walk the main flow on staging
   and note friction, broken copy, wrong language, missing empty/error states.
5. The milestone closes only when the suite is green on staging. You give the final verdict.
6. Commit after every step; push the branch right after the first commit, then after every commit.
7. Reports at most 6 lines. No ack-only messages. Rotate at ~250k context with a handover note.
