# State files: what goes where

The ledger is a private git repo. Its layout is the same for every project:

```text
<ledger repo>/
  COORDINATION.md          live state only (budget: 80 lines)
  coordination/
    README.md              read order, units and repos to clone, anything needed to set up
    PROFILE.md             how this project runs (see profile.md); the owner's standing rules
    ROADMAP.md             goal, milestones if used, ordered backlog per unit, verification debt
    DECISIONS.md           append-only decision log (C-xxx)
    handover/              one file per role, overwritten at each rotation (git keeps history)
    memory/                portable copy of the coordinator's memory files
    MOVE.md                optional: steps to continue on another machine
```

Where the ledger repo sits:

- `multi-repo`: the ledger repo **is** the workspace root. Unit repos are cloned into
  `products/<unit>/` and git-ignored by the ledger (`/*` ignored, then `COORDINATION.md` and
  `coordination/` re-included).
- `single-repo`: the ledger repo is a sibling folder of the project, named
  `<repo>-coordination`.

## One home per fact

| Fact | Home | Not in |
|---|---|---|
| What is true right now: per unit, what is released, what is in progress, what is blocked; what the owner must do next | `COORDINATION.md` | anywhere else |
| How we work: units, roles, flow, gates, limits, owner rules | `PROFILE.md` | the ledger, handovers, memory (memory may point here) |
| What comes next, in order; what is still unverified | `ROADMAP.md`, each item linking to an issue | the ledger |
| Why something is so | `DECISIONS.md`; one line with the same id in each unit it binds | the ledger |
| What happened | git history and merged PRs | any ledger file |
| Knowledge about a unit's code (traps, commands that work, flaky tests) | that unit's own docs, in the PR that found it | handover notes |
| What is in flight in one session | `handover/<role>.md` | the ledger |
| How a machine is set up (paths, auth workarounds, session ids, work windows) | that machine's local memory or the agent brief | every ledger file |

## `COORDINATION.md` shape

Template: `templates/COORDINATION.md`. Sections, in order: header with `Updated:` date; one
table of units (released, integration ahead by, in progress, blocked on); owner queue (what
only the owner can do, in order); active delegations with their expiry; open review points.

Rules:

- **Delete, do not append.** When an item is done, remove it. A merged PR needs no line.
- **A delegation expires.** "The owner delegated X for this session" must carry a date and is
  deleted when the session ends. A stale delegation reads as a standing permission.
- **Sessions are found by name**, never by id. Ids differ per machine.
- Commit and push after every change that another session would need: a merge, a decision, a
  release, a session start or rotation, an owner answer.

## `ROADMAP.md` shape

Template: `templates/ROADMAP.md`. The goal in two lines; milestones with exit criteria if the
cadence uses them; then, per unit, an ordered list of the next issues (`#N title`), with
"blocked on" where needed; then the verification debt list: every `UNVERIFIED` claim, with
what would verify it.

An item without an issue is an idea, not backlog. Either create the issue or leave it under
"Ideas".

## `DECISIONS.md` shape

Template: `templates/DECISIONS.md`. One table row per decision: id, date, who decided (owner
or coordinator), which units it binds, the decision in one or two sentences. Never edit a
row's meaning; add a new row and mark the old one `superseded by C-xxx`.

When a decision binds a unit, that unit's next PR in the area adds a one-line entry with the
same id to the unit's own decision log, so that agents working only in that repo can resolve
the id.

## Handover notes

Template: `templates/handover.md`. One file per role (`handover/coordinator.md`,
`handover/<unit>.md`), overwritten each time. Written straight into the ledger repo, not
copied from somewhere else. Units in `per-issue` mode have no handover file.

## The ledger lint

`scripts/ledger-lint.sh <ledger-dir>` checks what a machine can check: required files, size
and line-length budgets, session ids and home paths, decision ids that are cited but not
defined, a missing or old `Updated:` date. Run it before every ledger commit; procedure `audit.md`
runs it together with the checks that need judgement.
