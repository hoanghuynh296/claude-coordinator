# {{PROJECT_NAME}}: roadmap

What comes next, in order. An item is backlog only when it has an issue; everything else is
under "Ideas". The coordinator keeps at least the next two items per unit as issues, each placed in a group.

## Goal

<Two lines: what the project is for and what "done for now" means.>

## Milestones

<Only for milestone cadence. Otherwise delete this section.>

| Milestone | Content | Exit criteria (how we know) | State |
|---|---|---|---|
| <M1> | <what> | <observable outcome> | <planned, running, closed> |

## Backlog per unit: release groups (ordered)

Each group is one theme with a target version; a group is released when all its issues are
merged and its verification debt is cleared. Large = own group; small rides with an open
group or a patch batch group.

### <unit>

#### Group <name> → v<X.Y.Z> (large|small)
Blocked by debt: <verification debt rows that must clear first, or nothing>
1. <owner/repo#N title> <(blocked on: ...)>
2. <owner/repo#N title>

#### Group <next name> → v<X.Y.Z> (large|small)
1. <owner/repo#N title>

## Verification debt

Every claim merged as `UNVERIFIED`, with what would verify it. Cleared at release.

| What | Where | Verified by |
|---|---|---|
| <claim> | <PR or file> | <the check that would settle it; who can run it> |

## Release notes draft

Added to as PRs merge, so the release does not start from a blank page. Per unit, one line per
user-visible change (PR link). Cleared at release.

- <unit>: <change> (<owner/repo#N>)

## Ideas (no issue yet)

- <idea>

## Open questions for the owner

1. <question, with what it blocks>
