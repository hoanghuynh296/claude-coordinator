# Workflow: full lifecycle

## 1. Kickoff (`/coordinator:kickoff`)
1. Interview the owner, five questions in one message: (1) product and the problem, users and
   personas; (2) the design partner (alias only) and what they need first; (3) stack preferences
   and constraints (hosting, languages, AI provider, UI language); (4) scope of MVP1 and what is
   explicitly later; (5) owner availability, budget limits, repo name/owner.
2. Write the draft `docs/PLAN.md` in the scratchpad from the template sections (summary,
   principles, users, scope by phase, UX, AI, architecture, milestones with QA exit criteria,
   agent workflow, owner-side tasks, MVP done, risks). Generalise every design-partner need into a
   per-tenant-configurable feature.
3. **Stop.** Ask the owner to approve or change the plan. Nothing is created before approval.

## 2. Bootstrap (after approval)
1. Write the placeholder values file (keys from the template's `TEMPLATE.md`: PROJECT_NAME,
   PROJECT_DESCRIPTION, OWNER_GITHUB, UI_LANGUAGE, STACK_*, API_DIR, WEB_DIR, INTEGRATIONS_DIR,
   AI_DIR, CMD_*, CONTRACT_FORMAT, FIRST_CUSTOMER_ALIAS). The `*_DIR` values also feed the CI
   paths-filter in `.github/workflows/ci.yml`; a lane not needed still gets a dir value and is
   trimmed by Platform's first ticket. Commands not known yet: `make <target>` stub text such as
   `TBD (platform)`.
2. Run `scripts/bootstrap.sh <owner/repo> <dir> --values <file> --plan <PLAN.md> [--check <job>]`.
   It creates the repo from `hoanghuynh296/agent-project-template`, fills placeholders everywhere,
   deletes `TEMPLATE.md`, creates and pushes `develop`, sets default branch + delete-branch-on-merge,
   labels `lane:*` `milestone:*` `decision`, GitHub milestones, the private `<repo>-coordination`
   ledger repo with `COORDINATION.md` + `handover/`, and branch protection (required check
   `changes` + extras) on develop and main.
3. Register the session as coordinator (`scripts/register.sh`). From now on the guard hook is on.
4. Write the owner-side task list into the ledger (accounts, domains, secrets, billing, design
   partner contacts) and send it to the owner in one message.

## 3. Milestone start (`/coordinator:milestone-start`)
1. Create one Issue per ticket from the ticket form: milestone, lane, goal, allowed paths,
   contract, acceptance criteria, required tests (3 fixture domains), out of scope. Labels
   `lane:<lane>` + `milestone:<Mn>`.
2. **Contract first.** The contract ticket (api lane, `docs/contracts/`) merges before parallel
   backend/frontend tickets start. Until then, only tickets that do not depend on it run.
3. QA ticket: acceptance tests from the exit criteria.
4. Fill the milestone table in the ledger; commit + push.
5. **Start every session the milestone needs in this one owner turn**: lane sessions, Platform,
   QA. Sessions can only be started from the owner's own message in the desktop app; if you wait
   for a later turn you need another owner message. Name them "Agent: <lane>", set the model,
   own worktree, the lane brief as background and the ticket as prompt.
6. Fallback when sessions cannot be started (owner on Remote Control / mobile, or the tool is
   unavailable): run the same brief as background subagents with worktree isolation; they push
   and open PRs themselves. Mark them `subagent` in the Sessions table and convert them to lane
   sessions when the owner is back at the desktop (handover note -> fresh session, same name).

## 4. Lane loop (lanes do this, not the coordinator)
Branch `t<m>.<n>-<slug>` from fresh `develop` -> commit after each step, push after the first
commit and every commit after -> PR `Closes #N` with the template -> Auto-fix on -> fix CI
until green -> report "PR ready + CI green" or "blocked/decision" in at most 6 lines.

## 5. Review and merge (`/coordinator:review-merge`)
1. Check CI is green and the diff stays inside the ticket's allowed paths.
2. Reviewer subagent: **mandatory** for auth, tenancy/isolation, money/billing, AI write tools
   (agents that change data), secrets or permissions; also for large PRs (> ~400 changed lines
   or > 15 files). Otherwise a coordinator skim against `review-checklist.md` is enough.
3. Blocking findings -> one batched message to the lane; it fixes on the same branch.
4. Stacked PR? Retarget it to `develop` before merging its base, or its commits are lost.
5. Merge (squash) into `develop`. Update the ledger row, commit + push the ledger. Tell QA to
   run the suite when the merge touches an exit criterion (batched with other news).

## 6. Milestone close (`/coordinator:milestone-close`)
1. QA verdict: suite green on staging for every exit criterion.
2. Demo instructions for the owner: staging URL, test accounts (from the project's seed files),
   3-6 steps per persona, what to look for.
3. After the owner's OK: release branch `release/<version>` from `develop`, bump `VERSION`,
   update `CHANGELOG.md`, PR `release/<version>` -> `main`. Release PRs must come from
   `release/*` branches: the release workflow tags `v$(cat VERSION)` only for those.
4. The owner merges the release PR; the workflow creates the tag and GitHub release.
5. Merge `main` back into `develop` if they diverged (via PR). Close the GitHub milestone, write
   follow-ups into the ledger, rotate sessions that are near the limit.

## 7. Continuous rules
- Measure contexts on each owner message (`scripts/check-context.sh`); rotate at ~250k.
- Ledger commit + push after every merge, decision, session change.
- One batched message per agent per round; no ack-only or status pings.
- Usage limit hit: all agents stop at once. After the reset, resume each agent with SendMessage
  (its transcript and worktree survive); do not start new ones. The ledger tells you who was
  doing what.
