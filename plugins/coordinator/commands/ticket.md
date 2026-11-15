---
description: Create one ticket as a GitHub Issue from the ticket form fields (goal, lane, allowed paths, contract, acceptance, tests)
argument-hint: "<lane> <short goal>"
---

Create one ticket for: `$ARGUMENTS`.

1. Determine milestone (current one from the ledger), lane, and the next number `T<m>.<n>`.
2. Check `OWNERSHIP.md`: the allowed paths must be owned by that lane. Shared/root files ->
   Platform lane. Cross-lane needs -> split into two tickets or go through the contract.
3. Body, matching the repo's ticket form (`.github/ISSUE_TEMPLATE/ticket.yml`):
   ```
   ### Milestone
   <Mn>
   ### Lane
   <lane>
   ### Goal
   <what and why, 2-5 lines>
   ### Allowed paths
   <globs>
   ### Contract / interface
   <link to docs/contracts/... or "none">
   ### Acceptance criteria
   - [ ] ...
   ### Required tests
   <unit/integration/e2e; fixtures from at least 3 domains where relevant>
   ### Out of scope
   <...>
   ```
   No customer names or domain terms of the design partner; describe the generic,
   per-tenant-configurable feature.
4. `gh issue create --repo <repo> --title "T<m>.<n> <title>" --label lane:<lane> --label milestone:<Mn> --milestone <Mn> --body-file <scratchpad file>`.
5. Add the row to the ledger milestone table; commit + push the ledger. Reply with the Issue link
   only. Hand it to the lane in your next batched message to that lane, not as a separate ping.
