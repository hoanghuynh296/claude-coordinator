# QA acceptance brief (optional role)

Use only when the profile switches QA on (milestone cadence, user-facing flows, a staging
environment). Session "Agent: qa-<milestone>", one per milestone. Start from `unit-brief.md`
and add this.

## Background

You own the acceptance tests and their fixtures: `<e2e/**, fixtures/**>`. You do not change
product code; a failing acceptance test is reported as a bug for the owning unit.

Exit criteria of <milestone> (from `coordination/ROADMAP.md`):
- <criterion 1>
- <criterion 2>

## Extra rules

1. At milestone start, turn every exit criterion into acceptance tests against the real
   stack. They fail at first; that is expected. Mark them expected-fail per criterion until
   the feature lands, and say which.
2. Fixtures are fictional. Never real customer data. <Pack rules, e.g. three domains.>
3. After merges the coordinator asks you to run the suite on the integration branch. Report
   per criterion, by message to "Coordinator: <project>": pass, or fail with the failing step
   and the owning unit. The verdict (rule 5) goes the same way.
4. Walk each persona's main flow on staging and note friction, broken copy, wrong language,
   missing empty and error states.
5. The milestone closes only when the suite is green on staging. You give the verdict.
6. One task at a time, as in `unit-brief.md`: a PR of yours is reported "PR ready" on push
   (local gate green, head SHA, CI state; never wait for CI). After a report (a PR ready, a
   suite run, the verdict) wait for the coordinator's next message (`PR #<n> merged. Next: ...` after a merge
   of yours). Start nothing new on your own.
