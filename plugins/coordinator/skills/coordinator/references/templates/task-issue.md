# Task issue body

The body of every task issue (`/coordinator:ticket`). An agent starts from this text alone, so
write it for a reader who has not seen the conversation. Label: `task` plus `unit:<unit>` in a
single-repo project; add the milestone if the cadence uses one.

```markdown
## Goal
<What should be true afterwards, and why. Two to five lines.>

## Acceptance criteria
- [ ] <observable outcome>
- [ ] <observable outcome>

## Checks that prove it
<The unit's gate, plus anything specific: a test to add, a run to dispatch, a screen to open.
Say what evidence the PR must carry.>

## Scope
- In: <paths or areas>
- Out: <what not to touch or solve here>

## Depends on
<Issue links, contract versions, an owner task. "Nothing" if so.>

## Notes
<Pointers: files to read first, decision ids, prior attempts and why they failed.>
```

Rules for the writer:

- One issue is one PR. If it needs two units, write two issues and link them.
- A contract or format change is its own issue and comes first.
- Acceptance criteria describe outcomes, not steps.
- Anything that needs the owner (a secret, a purchase, a device) is listed under "Depends
  on" and also in the owner queue of `COORDINATION.md`.
