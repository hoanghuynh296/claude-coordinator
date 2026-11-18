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
   - coordinator-released unit: do it, then check the result. One release standard for
     repos with a `develop`: branch `release/vX.Y.Z` from `develop`, PR into `main` (head
     `release/vX.Y.Z`, never `develop`, so delete-branch-on-merge is safe and the Next guard
     skips it). Merge the release PR with a **merge commit, never a squash** (a squash makes
     later back-merges diverge). Tag the merge commit, then the back-merge (step 6). A repo
     released by tag only: tag the integration branch and publish.
   - owner-released unit: prepare it and ask the owner. Do not merge it yourself unless the
     owner delegated this release in this session; a delegation is written into
     `COORDINATION.md` with its date and deleted afterwards.
6. **Back-merge** (repos with a `develop`): after the tag, merge `main` into `develop` (a PR
   from a `backmerge/vX.Y.Z` branch cut from `main`, or a fast-forward if `develop` has not
   moved), so `develop` holds the release commit. Never delete `develop`. On a conflict:
   resolve it on the `backmerge/vX.Y.Z` branch (never on `develop` or `main`), re-run the gate
   there, and never force-push `develop` or `main`.
   **Branch names:** the coordinator's own PRs use `release/vX.Y.Z`, `backmerge/vX.Y.Z` or
   `coordinator/<topic>` heads; the Next guard exempts exactly these (header of
   `hooks/merge-reminder.sh`; `$COORDINATOR_GH_LOGIN` also exempts by author, never set it to an account agents share).
7. **Ledger.** Update the unit's row (released = the new version, ahead by 0), remove the
   cleared debt rows, close the milestone in `ROADMAP.md` and on GitHub. Lint, commit, push.
8. Measure contexts; replace `SOFT` and `HARD` sessions before the next stretch. If the unit
   was in a feature freeze because of its integration limit, the freeze ends here.
