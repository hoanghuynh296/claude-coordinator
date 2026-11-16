# Core principles

These eight rules hold for every project, whatever its shape. Everything else is a choice the
project records in its `PROFILE.md` (see `profile.md`). When a profile choice seems to conflict
with a principle, the principle wins and the profile is wrong.

Each rule names the failure it prevents. All of these failures happened in real projects.

## 1. One owner, one coordinator

The owner talks to one coordinator session. The coordinator steers every other session. Only
real decisions reach the owner: scope, anything that costs money, anything the profile marks
owner-only. Questions are batched into one message, decisions first.

*Prevents:* the owner relaying messages between agents, and cross-unit agreements drifting
apart because nobody held all of them.

## 2. State lives in files and on GitHub, never only in a session

A session can die at any time (usage limit, crash, rotation, a move to another machine). So:

- The ledger holds **live state only**, inside a size budget. Finished items are deleted; their
  history is already in git and in merged PRs.
- Each kind of fact has exactly **one home**: live state in `COORDINATION.md`, how the project
  runs in `PROFILE.md`, what comes next in `ROADMAP.md`, why things are so in `DECISIONS.md`.
- Nothing machine-specific goes into the ledger: no home paths, no session ids, no local auth
  workarounds.

*Prevents:* a ledger that grows into a 200-line log nobody can read, the same rule copied to
three places with three different values, and state that cannot move to another machine.

## 3. Work is an issue with acceptance criteria

Every task is a GitHub issue that says what done looks like. One issue, one branch, one PR.
An agent's brief is "do issue #N" plus the stable brief of its unit. The ordered backlog of
each unit is in `ROADMAP.md`, so an agent that finishes always has a next item.

*Prevents:* tasks that exist only in a chat message, agents idling while their unit has work,
duplicate PRs, and work that stops silently.

## 4. Units own their ground; units meet at a versioned contract

Each unit (a lane of directories, or a whole repo) has exclusive ownership. A unit never edits
another unit's files. Where two units depend on each other, they meet at an artifact with a
version: an API schema, a lock file with checksums, a tagged data release. The contract merges
before the work on either side of it starts.

*Prevents:* merge conflicts on shared files, and two sides building against two guesses.

## 5. The author never approves their own work; evidence beats claims

Whoever wrote a change does not merge it. Review reads the diff and checks the evidence (a CI
run id, command output, a screenshot), not the author's summary. The author's tests share the
author's blind spots, so risky areas get an independent reviewer. Anything not verified is
labelled `UNVERIFIED` and tracked until someone verifies it.

*Prevents:* "tests pass" standing in for "it works", and unverified claims quietly becoming
facts.

## 6. Integration is bounded

The profile sets a limit on how far the integration branch may run ahead of the last release
(a number of PRs, or days). At the limit, feature work in that unit stops and verification and
release come first.

*Prevents:* agents producing changes faster than anyone can verify them, until a release needs
a review of thirty PRs at once.

## 7. A rule that matters is enforced by a machine

Hooks, CI, repository settings and the ledger lint enforce what they can. A rule that lives
only in a prompt or in memory gets broken under pressure. When the same mistake happens twice,
add a mechanical guard instead of a stronger sentence.

*Prevents:* the coordinator editing product code "just this once", pushes onto branches whose
PR already merged, ledgers drifting out of shape.

## 8. Lean messaging; knowledge goes where it is used

- No ack-only or status-ping messages, in either direction. Silence means "working".
- One batched message per agent per round. Short reports (the profile sets the length).
- Sessions are replaced past the profile's context thresholds, not kept alive: after their
  current issue at the soft one, at the next safe point at the hard one.
- What an agent learns about a unit goes into that unit's own docs, in the same PR. A handover
  note carries only what is in flight, never knowledge about the code.

*Prevents:* token burn from sessions waking each other up, and traps that only one session
knew about being lost when it rotates.
