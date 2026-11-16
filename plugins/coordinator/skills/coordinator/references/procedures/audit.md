# Procedure: Audit the coordination state

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Audit the project's coordination state. Run this once per
working day, before every handover, and whenever the ledger feels wrong.

1. **Mechanical lint:**
   `bash "<plugin>/scripts/ledger-lint.sh" <ledger-dir>`
   Fix every error (the message names the file and the rule). Typical fixes: delete finished
   items from `COORDINATION.md`; move a rule to `PROFILE.md`; add a missing decision row;
   remove a session id or a home path.
2. **Drift against GitHub**, per unit repo: open PRs and open `task` issues against the
   ledger's "In progress" and the roadmap's lists; how far the integration branch is ahead of
   the release branch (`gh api repos/<repo>/compare/<release>...<integration> --jq .ahead_by`)
   against the ledger's "Integration ahead by". GitHub is right; fix the ledger.
3. **Integration limits:** any unit at or over its limit and still receiving feature issues?
   Stop them; the next item for that unit is verification and release.
4. **Idle units:** any unit with an unblocked backlog item and nobody on it? Hand it out in
   the next batched message (or say why not, for example an owner-set pause).
5. **Backlog depth:** every unit has at least its next two items as issues, or its list says
   "nothing planned".
6. **Verification debt:** every `UNVERIFIED` in recent merge notes has a row; rows a release
   has covered are removed.
7. **Delegations:** every entry under "Active delegations" has a date and is still valid;
   delete the rest.
8. **Decisions:** anything decided since the last audit has a row in `DECISIONS.md`; units a
   new decision binds have (or have an issue for) their one-line entry.
9. **One home per fact:** a rule that appears in two files is deleted from all but
   `PROFILE.md`. Knowledge about a unit's code found in a handover note moves to that unit
   (an issue or a docs PR).
10. **Profile fit:** does a recurring problem point at a profile choice
    (`references/profile.md`, "Changing the profile")? Propose one change to the owner.

Commit and push the ledger. Report in at most 8 lines: what was wrong, what you fixed, what
needs the owner.
