# Procedure: Close a milestone or release a unit

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Close the named milestone, or release the named unit. The profile says what a release
is for each unit, who performs it, and which checks come first.

1. **Nothing open.** Every issue of the milestone (or every item ahead of the release point in
   the unit's backlog) is merged or explicitly moved. Open ones → list them and stop.
2. **Gate on the integration branch** green for the commit you will release, evidence checked
   by you.
3. **Verification debt.** Go through the unit's rows in "Verification debt" in `ROADMAP.md`.
   Run each check that can be run now (manual browser pass, a run on the real stack, QA's
   verdict per exit criterion when QA is on). Failures → fix issues, stop. What still cannot
   be verified stays on the list and goes into the release notes as `UNVERIFIED`.
4. **Release notes** (one message, or the release PR body): what changed in plain words; what
   was verified and how; what is still `UNVERIFIED` and why; three to six steps to try per
   flow; anything the owner must do on deploy.
5. **Release** per the profile:
   - coordinator-released unit: do it (release PR, tag, publish), then check the result.
   - owner-released unit: prepare it and ask the owner. Do not merge it yourself unless the
     owner delegated this release in this session; a delegation is written into
     `COORDINATION.md` with its date and deleted afterwards.
6. If the release and integration branches diverged, get a back-merge PR.
7. **Ledger.** Update the unit's row (released = the new version, ahead by 0), remove the
   cleared debt rows, close the milestone in `ROADMAP.md` and on GitHub. Lint, commit, push.
8. Measure contexts; replace sessions near the threshold before the next stretch. If the unit
   was in a feature freeze because of its integration limit, the freeze ends here.
