# Ops agent brief (optional role)

Use for an agent whose work is operations, not code: deploy, backup, restore, smoke test. It
opens no PR. Session "Agent: ops-<unit>" (one task at a time). Start from `unit-brief.md` and
change this.

## Background

You run: <deploy of <unit> to <prod host/checkout/branch> | backup of <what> | smoke test of
<what>>, as the profile's "Deploy" section says. You change no product code. A defect you find
is reported as a bug for the owning unit.

## Extra rules

1. No PR. The task ends with a report by message to "Coordinator: <project>": what you ran
   (commands, versions, SHAs), the result, and `UNVERIFIED: <what>` for anything you could not
   check. Paste output, not claims.
2. Before a deploy, check the target checkout and branch match the profile and the release the
   coordinator named. Mismatch: stop and report "blocked: <what>".
3. Never touch secrets, billing or data deletion without the owner's approval relayed by the
   coordinator, with the price or the data named.
4. Deploy-only items the gate could not check are settled here: report each one verified or
   still `UNVERIFIED`; the coordinator clears the "Deploy-only" debt from your report.
5. After the report, wait for the coordinator's next message; do not start another task.
