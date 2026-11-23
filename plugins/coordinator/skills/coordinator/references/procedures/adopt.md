# Procedure: Adopt the kit in an existing project

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Adopt the kit in an existing project. Input (optional): the ledger folder and the unit folders.
Adoption changes how work is tracked, not the product.

## Step 1 - read what is there
- Repos and folders, default and integration branches, CI workflows, branch settings
  (`gh repo view --json defaultBranchRef,deleteBranchOnMerge`).
- Open issues and PRs, how far each integration branch is ahead of its release branch.
- Each unit's `AGENTS.md` and docs: do they carry enough for a cold start?
- Any existing coordination notes: a ledger, handover notes, memory files, a plan.
- Running agent sessions and what they are doing.

## Step 2 - propose a profile (one message, then wait)
Draft `PROFILE.md` from `references/templates/PROFILE.md` so that it describes how the project
already works, and list separately what you would change and why (for example: an agent that
idles → `per-issue`; no release rule → groups plus a safety ceiling; decisions cited but defined nowhere →
`DECISIONS.md`). Ask the owner to approve. **Change nothing before the owner approves.**

## Step 3 - create or migrate the ledger
- No ledger: `bash "<plugin>/scripts/init-ledger.sh" <ledger-dir> --name "<Project>" --owner <github-user>`.
  It never overwrites an existing file.
- Existing ledger: sort every line of the old files into its one home
  (`references/state-files.md`):
  - live state → `COORDINATION.md` (delete what is finished; history is in git);
  - rules → `PROFILE.md`, once;
  - next work → `ROADMAP.md`, as issue links (create the missing issues);
  - decisions → `DECISIONS.md`, keeping their ids;
  - knowledge about a unit's code → an issue or a docs PR in that unit;
  - machine-specific notes → out of the ledger (local memory or the agent brief).
  Remove session ids, home paths and expired delegations.
- Run `bash "<plugin>/scripts/ledger-lint.sh" <ledger-dir>` until it passes.

## Step 4 - guards and labels
- `bash "<plugin>/scripts/install-guards.sh" --settings <unit-dir>...`
- Label `task` in each repo (`unit:<unit>` too in a single-repo project).
- One short docs PR per unit: the "how work arrives" rules in its `AGENTS.md`, and a one-line
  entry for each decision that binds it.

## Step 5 - register and report
Follow the `coordinator-register` procedure (ledger dir, unit dirs), then the `audit` procedure, commit and
push the ledger. Registration reads the app settings (`mcp__ccd_settings__get_settings`): if
`auto_archive_on_pr_close` is on, ask the owner to turn it off before any agent starts, and
record the result in `PROFILE.md` ("Flow"). Report to the owner in at most 10 lines: what moved where, what was deleted,
what is now enforced by a machine, what you need from the owner.
