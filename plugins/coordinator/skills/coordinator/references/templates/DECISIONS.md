# {{PROJECT_NAME}}: decisions

Append-only. One row per decision; never delete or rewrite a row, add a new one and mark the
old one `superseded by C-xxx`. `owner` = decided by the owner; `coordinator` = decided by the
coordinator, the owner may veto. Every unit a decision binds carries a one-line entry with the
same id in its own docs.

| ID | Date | By | Binds | Decision |
|---|---|---|---|---|
| C-001 | {{DATE}} | owner | all | Coordination follows the `claude-coordinator` kit: core principles plus this project's `PROFILE.md`. |
