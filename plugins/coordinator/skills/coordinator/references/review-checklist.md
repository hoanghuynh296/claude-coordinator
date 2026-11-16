# Review checklist (core)

Used by the Reviewer subagent and by the coordinator's own review. Report only real findings,
ranked high / medium / low, each with `file:line` and a concrete fix. Add the checklists of the
packs the project's profile lists (`packs/*.md`).

## Evidence
- The unit's gate is green, and you saw the evidence yourself: the CI run for this head
  commit, or the command output. A report that says "tests pass" is not evidence.
- Every check the gate does not cover is named, and either done or marked `UNVERIFIED`.
- New claims in docs or comments ("matches the vendor output", "safe on existing data") have
  something behind them: a test, a run id, a citation.

## Correctness
- The issue's acceptance criteria are met, including edge cases: empty, large, concurrent,
  error paths.
- Tests exercise the behaviour and its failure paths, not only the happy path. A test that
  cannot fail is not a test.
- Migrations and format changes are reversible or safe on existing data.
- Blocking work (subprocess, network) has a timeout and does not run on an event loop.

## Scope
- The diff touches only the unit's ownership and the issue's scope.
- No unrelated refactors. No edits to another unit's files or to shared files the unit does
  not own.
- A contract between units changed only through its own issue, with the version bumped.

## Safety
- No secrets in code, tests, fixtures, logs or error messages.
- Input from outside is validated at the boundary; file paths are confined to their roots; no
  shell or eval with outside input.
- Nothing in a test can reach real hardware, real customers, a paid service or production
  data.

## Docs and state
- The docs the change makes stale are updated in the same PR (the unit's own rules say which).
- What the author learned the hard way is in the unit's docs.
- The plan or roadmap item is ticked or adjusted.
