# claude-coordinator

A Claude Code plugin marketplace with one plugin, **`coordinator`**: a reusable way to run a
software project with several Claude sessions, whatever the project's shape.

It has two layers:

- **Core principles**, the same for every project: one owner and one coordinator; state in
  files, not in sessions; work as issues with acceptance criteria; units that own their ground
  and meet at versioned contracts; independent review with evidence; releases by feature group with a safety ceiling;
  machine-enforced rules; lean messaging.
- **A project profile** (`coordination/PROFILE.md` in the project's ledger repo): how this
  project applies them. Nothing about the shape is assumed by the commands.

| The profile chooses | Examples |
|---|---|
| Topology | one repo split into lanes · several repos that feed each other · a mix |
| Units and how they are staffed | a standing session per unit · a fresh session per issue |
| Optional roles | Platform (shared files), QA (acceptance per milestone), Reviewer, one-off builder |
| Flow | integration and release branches, merge method, what a release is, milestones or a continuous backlog |
| Gates and limits | the exact command that must be green; how releases are grouped, and the safety ceiling on how far integration may run ahead |
| Authority | who releases each unit; what only the owner decides |
| Packs | `saas-multitenant`, `artifact-contracts`, `ui-product` |

Starting points for common shapes (a SaaS monorepo, a family of repos, one small repo, a
knowledge base, a library) are in the skill's `references/profile.md`.

## Install

```text
/plugin marketplace add hoanghuynh296/claude-coordinator
/plugin install coordinator@coordinator-marketplace
```

Or from a shell: `claude plugin marketplace add hoanghuynh296/claude-coordinator`, then
`claude plugin install coordinator@coordinator-marketplace`. Restart the session (or run
`/reload-plugins`) after installing. Requirements: `gh` (authenticated for your own repos),
`git`, `python3`; `jq` is used when present.

## For the owner: you only talk

You never have to type a command or learn the kit's words. Say what you want in your own
language; the coordinator session picks the procedure and follows the standard.

### Starting

| Situation | What you do | What you say (examples) |
|---|---|---|
| A new project | Open a session in the desktop app in an empty folder | "I want to build ...", "Mình muốn làm một app ..." |
| A project that already exists | Open a session in its folder | "Set this project up so agents can work on it", "Áp quy trình coordinator vào dự án này" |
| A project already under the kit | Open a session in its ledger folder | Anything: "tình hình sao rồi?", "what's next?" The session recognises the ledger by itself |

For a new project the coordinator asks five questions in one message (the product, its
shape, stack and limits, the first stretch of work, your working rules), then shows you a
draft plan and a draft profile. Nothing is created until you approve them.

### While the project runs

| You say | The coordinator does |
|---|---|
| "We need X", "thêm tính năng ...", "fix ..." | writes a task issue with acceptance criteria and queues it for the right unit |
| "Go", "bắt đầu làm đi" | starts or briefs the agents for the next stretch of work |
| "What's going on?" | status in at most ten lines, your decisions first |
| "Is it good? Merge it" | reviews with evidence, runs the independent Reviewer where the profile requires it, merges |
| "Release it", "chuẩn bị release" | verifies, writes release notes, releases, or hands the release to you |
| "I'm switching machines", "this chat is long" | writes the handover so a fresh session can continue |
| "Is everything in order?" | audits the ledger against GitHub and fixes drift |

### Where you are needed

Everything else runs without you. The coordinator stops and waits only for:

1. **Approving the plan and the profile** at the start.
2. **Owner-side tasks**: accounts, secrets, payment details, devices, sample data.
3. **Real decisions**: scope, priorities, anything your profile marks as yours.
4. **Money**: every choice that costs money, with its price.
5. **Starting agent sessions**: they can only be started in a turn you began from the
   desktop app, so the coordinator asks you to say "go" there.
6. **Releases of the units your profile gives you**, with the release notes in front of you.
7. **Checks only a human can do** (a real device, a real customer flow). Skipped ones are
   listed as `UNVERIFIED` in the release notes.

Questions arrive batched in one message. You get no status pings; silence means work is
going on, and "what's going on?" always gets an answer.

## The ledger

A private git repo with the same layout in every project:

```text
COORDINATION.md            live state only (80-line budget)
coordination/
  README.md                read order, units and repos, set-up notes
  PROFILE.md               how this project runs; the owner's standing rules
  ROADMAP.md               ordered backlog per unit (issue links), verification debt
  DECISIONS.md             append-only decision log (C-xxx)
  handover/<role>.md       what a session had in flight
  memory/                  portable copy of the coordinator's memory
```

Each kind of fact has one home. History is git and merged PRs, never the ledger. In a
multi-repo project the ledger repo is the workspace root and unit repos sit in `products/`
(git-ignored); in a single-repo project it is a sibling folder `<repo>-coordination`.

## Commands (optional shortcuts)

Each command runs the same procedure the skill picks from plain language
(`skills/coordinator/references/procedures/`).

| Command | What it does |
|---|---|
| `/coordinator:kickoff` | interview → draft plan and profile → owner approval → create ledger, repos, guards → register |
| `/coordinator:adopt` | existing project: propose a profile, create or migrate the ledger |
| `/coordinator:coordinator-register <ledger> [unit...]` | register this session as coordinator (edit guard, SessionStart reminder) |
| `/coordinator:ticket <unit> <goal>` | one task issue with acceptance criteria; adds it to the unit's backlog |
| `/coordinator:review-merge <repo>#<PR>` | gate evidence, scope, Reviewer when required, manual checks, merge per the profile |
| `/coordinator:milestone-start <name>` | issues contract-first, ordered backlog, agents started or briefed in one owner turn |
| `/coordinator:milestone-close <name>` | verify, clear verification debt, release notes, release by whoever the profile names |
| `/coordinator:handover [unit]` | handover note in the ledger, replacement proposal |
| `/coordinator:status` | concise status from the ledger and GitHub |
| `/coordinator:audit` | ledger lint, drift against GitHub, release groups and ceilings, idle units, stale delegations |

Also included: the `coordinator` skill (principles, profile guide, workflow, roles, state
files, review checklist, pitfalls, packs, templates) and two agents: `coordinator:reviewer`
(read-only) and `coordinator:oneoff-builder` (own worktree, own branch, own PR).

## Mechanical guards

| Guard | What it stops |
|---|---|
| Edit guard (PreToolUse hook) | a registered coordinator editing anything inside a unit except the planning files the profile allows. Understands several units, also when they sit inside the ledger folder. `register.sh --allow <glob>` sets the allowed files; `--no-guard` switches it off for projects whose profile lets the coordinator write code |
| Merge reminder (PostToolUse hook on Bash) | a registered coordinator forgetting, after `gh pr merge <N>`, to tell the author what is next or to archive a `per-issue` agent's session. It splits the command like a shell (`echo gh pr merge 9` does not count), confirms each PR with `gh pr view` (one 20 s deadline for all; `--auto` included, since a ready PR merges at once) and records `owner/repo#N` as "pending Next" only when it is MERGED (state in `~/.claude/coordinator/state/<session>/`); when gh cannot answer, or a `gh pr merge` cannot be parsed, it only reminds |
| Next sent (PostToolUse hook on `SendMessage` and `send_message`) | clears a PR when any message the coordinator sends holds `PR #N merged` (or `PR owner/repo#N merged`, needed when N is pending in two repos) and a `Next:` line, whatever the recipient |
| CI watch reminder (UserPromptSubmit hook, and PostToolUse on `ReadNotifications` / `FetchInboxMessage`) | a registered coordinator receiving "PR ready" and forgetting to start the background CI watch: it is reminded in that turn, with a ready-to-run `ci-watch.sh` command for each PR link in the message. A reminder, never a block |
| Next guard (Stop hook) | a coordinator ending its turn while a merged PR's author has not been told `PR #N merged. Next: ...`: the stop is blocked with the PRs and the message format; at most 3 blocks per turn, then a warning. `scripts/next-clear.sh <session> <owner/repo#N> "<reason>"` clears a PR whose author cannot be messaged, logging the reason to the ledger's `coordination/next-cleared.md` |
| `scripts/ledger-lint.sh <ledger>` | a ledger out of shape: missing files, over the size budget, session ids or home paths, decision ids cited but not defined, leftover placeholders. Warns on a stale date, on history in the live ledger, on an undated delegation |
| `scripts/pre-push-guard.sh` (git pre-push hook) | pushing to a branch whose pull request is already merged or closed; optional local protection of release branches |
| `scripts/install-guards.sh [--settings] [--tools "<groups>"] <repo>...` | installs the pre-push guard in each clone; `--settings` turns on delete-branch-on-merge on GitHub; `--tools` merges the lean agent tool set (every optional group of `scripts/agent-tools.json` not listed is turned off) into the repo's `.claude/settings.json` |

Limits: the edit guard covers the edit tools only; a shell redirection is not blocked. The
pre-push guard fails open when `gh` cannot reach the repo. A forked session gets a new session
id and must register again.

## Scripts

| Script | Purpose |
|---|---|
| `init-ledger.sh <dir> [--name] [--owner] [--workspace]` | write the standard ledger layout from the templates; never overwrites |
| `ledger-lint.sh [dir]` | see above; budgets in the environment or in `<dir>/.ledger-lint` |
| `ledger-commit.sh <ledger> "<message>" [path...]` | every ledger commit in one call: lint (errors only, nothing committed, exit 1), stage and commit only `COORDINATION.md`, `coordination/` and the extra paths (other changes stay unstaged and are counted), `pull --rebase --autostash`, push, one line `ledger-commit: <sha> pushed to <upstream> (<n> file(s))`. Rebase conflict: aborted, commit kept local (3); refused push (4); no upstream: commit only |
| `install-guards.sh`, `pre-push-guard.sh` | see above |
| `next-clear.sh <session> <owner/repo#N> <reason>` | clear a merged PR the Stop hook waits on, when its author cannot get the Next message; the reason is appended to `coordination/next-cleared.md` in the ledger. `--list` shows what is pending; `--handover` prints it and drops the session's state (written into the handover note); `--add <owner/repo#N>...` lets the replacement take it over |
| `merge-pr.sh <owner/repo> <N> <head sha> [--session] [--ledger] [--next] [--per-issue <name> --repo-dir <clone>]` | the mechanical part of review-merge in one call, at most 6 lines: refuses (exit 1, no merge) when the PR is not open, the head moved, or CI is red, pending or absent; merges with the profile method, `--delete-branch`, `--match-head-commit`; closes linked issues off the default branch; records the pending Next for the Stop guard (heads `release/*`, `backmerge/*`, `coordinator/*` exempt); prints the exact `PR #<n> merged. Next: ...` line, and for a per-issue author the session to archive and its worktree removed (`prune-worktrees.sh`) |
| `ci-watch.sh <owner/repo> <N> [<sha>]` | watch a PR's CI until it ends and print one line: `green` (exit 0), `red: <checks> <link>` (1, at the first failure), `error` (2), `stale-head` when the head is not or no longer the reported SHA (3), `timeout` (4, `CI_WATCH_DEADLINE`, default 90 min), `no-checks` (5, `CI_WATCH_NOCHECKS`, default 15 min), not open (6). The coordinator runs it with `run_in_background` on every "PR ready": its exit wakes the coordinator when CI ends |
| `register.sh <session> <ledger> [unit...] [--allow glob]... [--allow-none] [--no-guard]` | register or `--unregister` a coordinator session |
| `prune-worktrees.sh <root>... (--sessions <file> \| --no-session-check) [--apply] [--min-age-hours N] [--discard <glob>]...` | remove finished agent worktrees (`.claude/worktrees/*`) under the roots: only a registered, unlocked worktree with no change for N hours (default 6), a clean `git status` (or only changes matching `--discard`), HEAD in a remote branch, and (`--sessions`: the `list_sessions` JSON) no live session in it or on its branch and no open PR for its branch (`gh`; a failed lookup keeps it). `git worktree remove`, branches kept, stray folders reported and kept; prints the space freed. Dry run unless `--apply` |
| `check-context.sh [--role coordinator\|agent] [--profile PROFILE.md\|ledger] [--soft N] [--hard N] [--window N] [session...]` | context size per session from its transcript, with the threshold it used and a level: `334k / soft 300k: SOFT`. `ok`, `SOFT` (finish the current issue, then rotate) or `HARD` (rotate now). Role: a session titled `Coordinator: …` is a coordinator (soft 300k, hard 450k), any other an agent (250k / 400k); `--role` (or `--coordinator`) sets it for all. `--profile` reads the thresholds from the ledger's PROFILE Budgets (values it does not give keep the defaults). `SOFT_AT`, `HARD_AT` (agents only), then `--soft`, `--hard` (everyone) win over both. `--window` / `CONTEXT_WINDOW` caps soft at 50% and hard at 75% of the context window; one run per model group |
| `token-report.py <transcript dir \| session.jsonl> [--top N] [--json]` | where a session and its subagents spent tokens: calls, input, cache writes and reads, output, a weighted share, tool calls by tool, largest tool results; read-only (procedure `token-audit.md`) |
| `bootstrap.sh <owner/repo> <dir> ...` | the single-repo SaaS starting point: repo from a template (default `hoanghuynh296/agent-project-template`, which is private: pass `--template <your repo>`), placeholders, `develop`, labels, ledger, branch protection that requires the jobs of the new repo's `ci.yml` (the template's lane jobs, which always report; `--check` adds more; rerun after removing a lane). `--ledger-only` creates just the ledger; `--dry-run` prints every action |

## Layout

```text
.claude-plugin/marketplace.json
plugins/coordinator/
  .claude-plugin/plugin.json
  skills/coordinator/SKILL.md
  skills/token-audit/SKILL.md
  skills/coordinator/references/{principles,profile,workflow,roles,state-files,review-checklist,pitfalls,token-economy}.md
  skills/coordinator/references/procedures/*.md            (one per command; the skill routes to them)
  skills/coordinator/references/packs/{saas-multitenant,artifact-contracts,ui-product}.md
  skills/coordinator/references/templates/*.md
  commands/*.md
  agents/{reviewer,oneoff-builder}.md
  hooks/hooks.json, hooks/{lib,coordinator-guard,session-start,merge-reminder,next-sent,next-guard,ci-watch-reminder}.sh
  scripts/{init-ledger,ledger-lint,ledger-commit,merge-pr,install-guards,pre-push-guard,register,check-context,next-clear,ci-watch,prune-worktrees,bootstrap}.sh
tests/{hooks,ci-watch,merge-pr,ledger-lint,ledger-commit,pre-push-guard,structure,bootstrap,exec-bits,check-context,prune-worktrees}-test.sh
.github/workflows/tests.yml
```

## Tests

```sh
bash tests/hooks-test.sh           # edit guard, SessionStart, merge/Next/Stop hooks, CI watch reminder, jq and python3 paths, multi-unit workspace
bash tests/ci-watch-test.sh        # ci-watch.sh with a fake gh: green, red, stale and moved head, no checks, timeout, errors
bash tests/merge-pr-test.sh        # merge-pr.sh with a fake gh: refusals, flags, issue close, pending Next + Stop guard, exempt heads, worktree
bash tests/ledger-lint-test.sh     # every lint rule; a fresh ledger passes
bash tests/ledger-commit-test.sh   # ledger-commit.sh against a local bare origin: push, rebase, conflict, refused push, lint errors, hook, product files left out, extra paths
bash tests/token-report-test.sh    # token-report.py on a fixture session with a subagent
bash tests/pre-push-guard-test.sh  # merged, closed and open PRs with a fake gh; install-guards
bash tests/bootstrap-test.sh [template-dir]   # full bootstrap against local bare repos and a fake gh; required checks
bash tests/structure-test.sh       # commands, procedures and the skill agree; listing text fits the cap; key rules present
bash tests/exec-bits-test.sh       # every plugin *.sh is executable in git
bash tests/agent-tools-test.sh     # install-guards --tools: merge, idempotent, groups back on, refusals, catalog spares core tools
bash tests/check-context-test.sh   # ok / SOFT / HARD levels, roles, PROFILE Budgets, env and args, window cap
bash tests/prune-worktrees-test.sh # dirty, unpushed, live, open PR, young, locked, stray kept; clean pushed old removed; --discard
```

Gate for a kit PR: CI `tests` green (`.github/workflows/tests.yml` runs every `tests/*-test.sh`
on each PR and push to `main`, on a GitHub-hosted macOS runner). CI has no checkout of the private
agent-project-template, so `bootstrap-test.sh` runs there against a minimal template with the same
lane jobs; run it locally with the template path when a change touches `bootstrap.sh`.

## Changes

- **Unreleased**: `check-context.sh` is role- and profile-aware (#25, release group "Coordinator
  cost"). A session titled `Coordinator: …` gets the coordinator thresholds (300k / 450k) without
  `--coordinator`; `--role coordinator|agent` sets the role for every session listed
  (`--coordinator` stays as its short form). `--profile <PROFILE.md | ledger>` reads soft and hard
  per role from the profile's Budgets section, in the wordings the Semi Group ledgers use; a value
  it does not give keeps the kit default. Each line now names the threshold it used:
  `<session>  334k / soft 300k: SOFT  <title>` (was `334k  SOFT`); HARD lines name the hard
  threshold. `SOFT_AT` / `HARD_AT` apply to agents only, as before. Same output on Claude Code and
  Antigravity transcripts. `check-context-test.sh` covers both roles, the title rule and PROFILE
  overrides.
- `scripts/merge-pr.sh <owner/repo> <N> <head sha>` (#49, group "Coordinator cost"): the
  mechanical part of review-merge steps 1, 6 and 9 in one call with at most 6 lines of output.
  Refuses on a closed PR, a moved head, red, pending or missing CI; merges with the profile method,
  `--delete-branch` and `--match-head-commit`; closes linked issues off the default branch; records
  the pending Next itself (the merge-reminder hook does not see a `gh pr merge` inside a script), so
  the Stop guard still holds on Claude Code and Antigravity; `release/*`, `backmerge/*` and
  `coordinator/*` heads stay exempt (`next_exempt` in `hooks/lib.sh`). For a per-issue author it
  prints the session to archive and removes its worktree. `review-merge.md` uses it; the manual
  commands stay as the fallback. New `tests/merge-pr-test.sh`.
- `scripts/ledger-commit.sh <ledger> "<message>"` (#50, group "Coordinator cost"):
  lint, commit (ledger paths only, plus optional extra paths), rebase and push the ledger in one
  call with one line of output, replacing the
  separate lint / add / commit / pull / push calls. SKILL.md, `state-files.md`, `workflow.md`,
  `pitfalls.md` and every procedure that commits the ledger call it; `audit.md` installs the
  ledger-lint pre-commit hook where it is missing. New `tests/ledger-commit-test.sh`; the structure
  test checks the docs name it.
- `bootstrap.sh` no longer requires a `changes` check (#45). The template's fast CI
  (agent-project-template#4, C-045) has no `changes` job; each lane job decides in its first step
  and always reports. Branch protection now requires the jobs of the new repo's
  `.github/workflows/ci.yml` (so a removed lane is never required; rerun after removing one) plus any
  `--check` names; matrix jobs or jobs with an expression name are skipped with a warning (add them
  with `--check`). A private repo on GitHub Free still gets the 403 warning and continues.
  `bootstrap-test.sh` checks the default list, a protected rerun after removing a lane, and runs in
  CI against a minimal template when the private template is not checked out.
- **0.12.0** (2026-11-26): Antigravity alongside Claude Code (#40). Every hook reads both
  payloads (`session_id` or `conversationId`, `tool_input` or `toolCall.args`) and answers in
  the runtime's own format; Claude Code output is unchanged. New `plugins/coordinator/plugin.json`
  and `hooks.json` for Antigravity's plugin discovery (same version as the Claude manifest),
  a runtime mapping table in SKILL.md, `check-context.sh` also reads Antigravity transcripts
  (`ANTIGRAVITY_BRAIN_DIR`, default `~/.gemini/antigravity/brain`), and the coordinator guard
  allows `~/.gemini/**`. The agents keep their Claude Code frontmatter (tools, read-only
  Reviewer, model); on Antigravity they are marked `subagent: true` and run with its default
  tool set. On Antigravity the merge and Next-sent reminders are silent; the Stop guard still
  holds an unsent Next.
- **0.11.1** (2026-11-26): builder subagents may write when sessions cannot be started. When
  the owner is on Remote Control or the coordinator runs as a terminal CLI session, the
  coordinator re-registers with `--no-guard` before it starts `oneoff-builder` subagents (they
  inherit its edit guard), for that case only; it still writes no unit code, and re-registers
  with the guard on when sessions can be started again. SKILL, milestone-start,
  coordinator-register, profile reference and pitfall 28 updated.
- **0.11.0** (2026-11-26): token economy and token audit, lean agent tool set, finished
  worktrees pruned, and the other entries below.
  - Token economy and token audit. New `references/token-economy.md` (11 rules measured on a
    real release: fewer, bigger calls; summaries instead of logs and screenshots; local gate =
    affected tests; never idle past the prompt cache; a "Known" section in every brief;
    pre-flight before fan-out; codemods for mechanical work; model per task type; review where
    it pays; rotate the coordinator early; measure and improve). New procedure and command
    `token-audit` and a `token-audit` skill: measure → find the causes → general rule into this
    plugin → project rule into the profile → report. New `scripts/token-report.py` (read-only,
    python3 standard library): tokens, calls, cache reads and rewrites, tool calls and largest
    tool results per session and subagent from Claude Code transcripts. PROFILE template
    section 8 gets a "Token economy" block, the unit brief a rule 13 and a "Known" section,
    `review-merge.md` lets the coordinator check small fix commits outside risk areas from the
    diff. Test `tests/token-report-test.sh`.
  - Lean agent tool set (#27, owner decision C-018). `install-guards.sh --tools "<groups>"`
    merges into the unit repo's `.claude/settings.json` the rules that turn off every optional
    tool group of the new `scripts/agent-tools.json` not kept: `permissions.deny` for whole MCP
    servers and tools (a whole-tool deny drops them from the agent's context), `skillOverrides`
    `off` for skills, `enabledPlugins` false for plugins, `disableClaudeAiConnectors`. What it
    adds is recorded in `.claude/lean-tools.lock.json` and only that is ever removed: an entry
    the file already had is never removed, a different value (a skill at `name-only`) is kept
    with a warning. Other keys stay, a re-run is idempotent, a kept group is switched back on,
    broken JSON or an unknown group writes nothing; UTF-8 kept, atomic write, a symlinked
    settings file writes its target (`lean-tools.py`, needs python3). New "Tools" line in the PROFILE template (section 2) and the unit brief; profile
    reference, kickoff and adopt pass `--tools`. Existing units: run it once per unit repo and
    commit both files through a PR. Test `tests/agent-tools-test.sh`.
  - Finished worktrees are removed (#28, owner decision C-019: 25 GB of finished agent worktrees
    filled the disk). New `scripts/prune-worktrees.sh` (dry run by default, `--apply` removes)
    removes a `.claude/worktrees/*` worktree only when it is unlocked, unchanged for 6 hours,
    clean (or only `--discard` matches), pushed, and with no live session in it or on its branch
    and no open PR for its branch (a failed lookup keeps it); never a
    branch, never a stray folder. review-merge step 6: after archiving a `per-issue` session,
    check its worktree is gone, else prune it. Audit step 12: prune once per working day over
    the units (a group coordinator over the group's root folder).
  - UI draft gate (#29, owner decisions C-022 and C-023). Task issues of `ui-product` units carry
    `Draft: required | not needed` (new screen, layout change or multi-step flow → required).
    The agent first builds a mock-data draft, sends the owner three screenshots per screen
    (desktop, iPad, iPhone) and reports `Draft ready:` (draft URL, files), then waits; on the
    owner's approval the coordinator comments `Draft approved: <date>` on the issue and sends
    `Next: build #<n> (same session)`, the same issue's build phase and so exempt from the
    same-session conditions. Review: a `Draft: required` PR links the approval and keeps no
    `_draft` route. Changed: ui-product pack, task-issue template, ticket step 2, workflow
    sections 4 and 5, review-merge step 5, unit-brief rule 10, profile reference, SKILL.md.
    The agent-side Stop hook (#10, not shipped yet) must accept `Draft ready` as a report.
  - Defaults from owner decisions C-015 and C-017 (#24). Coordinator thresholds soft 300k,
    hard 450k on any model and window (agents stay 250k / 400k; `check-context.sh
    --coordinator`). Reviewer size trigger: over 400 changed lines or 25 hand-written files,
    not counting `CHANGELOG.md`, `VERSION`, `package*.json`, lockfiles, `public/**` mirrors,
    `**/vendor/**` (the profile may add more); a release PR is exempt when every feature PR in
    it passed review. Ledger: at most one commit per coordinator turn. Changed: SKILL.md,
    profile reference and template, workflow, handover, review-merge steps 4 and 7, state-files.
  - Same-session next issue only under 175k AND only when no session can start (#23, owner
    decision C-016). `Next: #m (same session)` now also needs that the coordinator cannot start
    a session this turn (Remote Control, an automated turn, a refused start); the context limit
    is a cap (default 175k, a profile Budgets line), not 50% of soft. Changed: SKILL.md Sessions,
    workflow, profile reference and template, review-merge step 9, pitfalls 37.
  - CI for the kit (#26): workflow `tests` runs every `tests/*-test.sh` on each PR and push to
    `main`; the kit's gate is now "CI `tests` green", not pasted output. Fixed on the way:
    `merge-reminder.sh` failed to parse under macOS `/bin/bash` 3.2 (heredoc inside `$(...)`).
  - Release groups (#30, owner decision C-039). Releases go by feature group, not by a PR count:
    the backlog in `ROADMAP.md` is ordered groups `Group <name> → vX.Y.Z (large|small)`; large
    (UI/API/visible/breaking or apps must act) is its own group released whole with migration
    notes, small rides with the open group or a patch batch, an urgent fix is a patch at once.
    The "Integration limit" becomes a safety ceiling (default 2 weeks or 15 PRs) that only stops
    new feature work. Changed: principle 6, profile reference and template ("Release" column),
    ROADMAP and COORDINATION templates, state-files, ticket (group and size every issue),
    review-merge step 8, workflow "Bound", milestone-close (notes per group), audit, status.
    ledger-lint accepts old and new profiles and warns when a unit row dated "since YYYY-MM-DD"
    is past the ceiling days (`CEILING_DAYS`, default 14) or a `Group` heading lacks
    `(large|small)`.
  - Migration (existing projects keep working until they migrate): in `PROFILE.md` rename the
    "Integration limit" column to "Release" and write `by feature group; ceiling <N weeks or M
    PRs>` (keep your old number as the ceiling); in `ROADMAP.md` regroup each unit's ordered
    list under `#### Group <name> → vX.Y.Z (large|small)` headings (one theme each, large items
    alone, small ones with an open group or a patch group) and put the debt that blocks a group
    under it; in `COORDINATION.md` write the open group in "Integration ahead by" (`n PRs,
    since YYYY-MM-DD; group <name>`). Log it in `DECISIONS.md` (C-039) and tell the agents.
- **0.10.0** (2026-11-18): one release standard, event-driven hooks, ledger-lint pre-commit,
  template gaps and an archive fallback.
  - Existing ledgers: re-run `install-guards.sh` (new pre-commit lint hook).
  - One release standard (#12). With a `develop`, a release is branch `release/vX.Y.Z` from
    `develop` → PR into `main` (a merge commit, never a squash) → tag → back-merge `main` into
    `develop` from `backmerge/vX.Y.Z` (conflicts resolved on that branch, no force-push);
    `develop` is never a PR head, so delete-branch-on-merge cannot delete it (milestone-close,
    workflow, PROFILE template, profile guide, kickoff, pitfall 10). The coordinator names its own
    branches `release/vX.Y.Z`, `backmerge/vX.Y.Z` or `coordinator/<topic>`. The Next-guard
    exemption is decided in `merge-reminder.sh` (the `gh pr view` that confirms the merge): a PR
    with a `release/*`, `backmerge/*` or `coordinator/*` head, or whose author is
    `$COORDINATOR_GH_LOGIN`, is never recorded as pending, so `next-guard.sh` makes no gh call (an
    agent naming its branch `coordinator/*` is exempt too; fail open when `gh` cannot answer).
    `COORDINATOR_GH_LOGIN` is optional and set in the hook environment (settings `env`); never set
    it to an account the agents share, it would exempt every agent PR. review-merge: the
    coordinator closes the linked issue after merging into `develop` ("Closes #N" fires only on the
    default branch). PROFILE template: a one-line note for tag-only repos.
  - hooks fire on events, not text (#11). merge-reminder reads the command as the
    shell would (heredoc bodies, comments and quoted text are ignored; `bash -c` and `eval` are
    read; the exit code is ignored) and records a merge only when `gh pr view`
    shows MERGED. The PR-ready reminder fires only when a message's FIRST line starts with
    `PR ready` (case-insensitive); the unit brief now tells agents to open their PR report with
    `PR ready:` and to use the phrase nowhere else (also in session-start, SKILL, roles and PROFILE).
    Merges the reader cannot parse (`bash -lc`, `$(...)`, backticks, `gh -R x pr merge`, sudo) still
    remind (fail open) or are read; a non-zero exit still checks `gh pr view`. Tests cover heredoc,
    quoted and progress-note false positives and these parser misses.
  - ledger-lint (#14): table rows are exempt from the line limit, `<project>:C-NNN` references to another ledger are allowed, a decision written as a bullet gets a message showing the row format, "Updated:" a day behind its last commit warns, and `install-guards.sh` installs a pre-commit hook in a ledger repo that runs the lint (nonzero exit on errors, tested). `profile.md` headings now match the PROFILE template (Owner rules is 11).
  - template gaps (#15). PROFILE gains "Deploy" (with a Deploy-only debt class) and
    "Files with no unit"; ROADMAP a "Release notes draft"; COORDINATION "Pending starts"; new
    `ops-brief.md` and a cross-lane mini-exception in `unit-brief.md`; review-merge and workflow
    gain the Reviewer re-run on fix commits, the contract/logic/UI split above the threshold,
    measured (not self-reported) context and the producer-ledger rule for cross-project items.
  - archive fallback. `archive_session` is refused in all six projects (the app's hook
    rewrites the input). The kit now says: call it; if refused with a rewritten input, call once more
    with exactly that input; if still refused, rename the session "<name> (old)" and add it to ONE
    owner-queue line "Archive finished sessions: <names>". `audit` checks that line and that no
    "(old)" session is still working.
- **0.9.0**: same-session next issue for `per-issue` agents, under strict conditions. The kit
  required a fresh session per issue and archiving after merge, but `archive_session` was refused
  in all six projects, session starts fail while the owner is on Remote Control, and a fresh
  session re-reads every doc for a small issue. The merge notice now has a same-session form,
  `PR #<n> merged. Next: #<m> (same session)`, which the coordinator sends only when `#m` is in the
  same unit, the agent's context (measured with `get_usage` / `check-context.sh`) is under 50% of
  the unit's soft threshold, `#m` is not in a Reviewer-mandatory risk area, and the session has
  done fewer than 3 issues in a row. Without `(same session)` the agent behaves as before. On it,
  the agent renames itself "Agent: <unit> #<m>" and branches fresh from the integration branch.
  `next-guard.sh` / `next-sent.sh` accept the form; docs and templates updated.
- **0.8.0**: agents report on push, the coordinator owns the CI wait. An agent pushed, saw CI
  queued on the single self-hosted runner and ended its turn, "I'll report once CI is green".
  Sessions run only when a message arrives and Auto-fix wakes an agent on CI failure only, so
  the green run woke nobody and the coordinator never heard "PR ready" (the mirror of the
  0.7.0 stall). Now an agent reports "PR ready" as soon as the PR is pushed and the local gate
  (lint and tests) is green, with the head SHA and the CI state then (pending, green or red),
  ending `Context: <k tokens>`; it never waits for CI. Review and CI fixes are reported the
  same way. On every "PR ready" the coordinator starts, in the same turn,
  `scripts/ci-watch.sh <owner/repo> <N> <sha>` with `run_in_background` (new: polls
  `gh pr checks` with a deadline, catches a moved head and a PR with no checks yet, prints one
  line: green / red / stale-head / timeout / no-checks), reviews in parallel, and merges only
  when CI is green on the reported head and the review passed (`--match-head-commit` in the
  merge command); after fixes it starts a new watch. A new hook reminds a registered
  coordinator to start the watch when a "PR ready" reaches it (UserPromptSubmit, and the inbox
  tools); a reminder only, since how messages arrive depends on the host. The 0.7.0 Next hooks
  are unchanged. Updated: the unit, platform and QA briefs, the PROFILE template, `profile.md`,
  `roles.md`, `workflow.md`, `review-merge.md` (step 2: start the CI watch), SKILL.md, the
  `oneoff-builder` agent, the SessionStart agent line, pitfall 32 "Both sides waited for CI".
- **0.7.0**: one issue, one full lifecycle. An agent reported "PR ready, next #50" and ended
  its turn; the coordinator merged and, as `review-merge.md` step 9 then said, told it nothing.
  Agent sessions run only when a message arrives, so both waited and nothing noticed. Now an
  agent takes ONE issue: PR, gate green, "PR ready" ending `Context: <k tokens>`, review fixes
  when told, then it waits and starts nothing new until the coordinator's
  `PR #N merged. Next: <issue | handover | stand by | done>`. The coordinator hands out one
  issue at a time (no more queues of two or three, no "continue without asking") and, in the
  same turn as the merge, reads the author's context (`get_usage`) and sends that message
  (soft limit reached: handover; `per-issue`: done, then archive). Hooks enforce it for a
  registered coordinator: the merge reminder records each merged PR as pending, a PostToolUse
  hook on `SendMessage` / `send_message` clears it when the notice is sent, and a Stop hook
  blocks the end of the turn while any is pending (at most 3 blocks per turn; escape hatch
  `scripts/next-clear.sh` with a reason logged in the ledger; `--handover`/`--add` carry pending PRs across a coordinator rotation). Updated: the briefs, the
  `oneoff-builder` agent, `workflow.md`, SKILL.md, `roles.md`, `profile.md`, the PROFILE
  template, `milestone-start.md`, `principles.md`, pitfall 31.
- **0.6.0**: a coordinator can no longer be lost to the app's "Auto-archive sessions when
  their pull request closes". The app binds every PR a session touches with `gh` (create,
  view, review, merge), so the 0.5.0 rule "unbind the PR after merging" was easy to miss, and
  two coordinators were archived anyway. Now `coordinator-register` (and so `kickoff` and
  `adopt`) reads the app settings and asks the owner to turn `auto_archive_on_pr_close` off,
  recording it in the profile; `audit` checks it again. Sessions are archived by the
  coordinator: after merging a `per-issue` agent's PR it archives that session
  (`archive_session`); a `standing` session is archived only on rotation. `unbind_pr` is kept
  only as the fallback while the setting is still on. A PostToolUse hook reminds a registered
  coordinator to archive the agent after every `gh pr merge`.
- **0.5.0**: all sessions are top-level peers. Whoever starts a session detaches it to the
  top level right away; a replacement is never started by the session it replaces. Agents
  report by message to "Coordinator: <project>" (PR ready, blocked, handover written), and a
  new coordinator tells every live agent its name. A coordinator names itself "Coordinator:
  <project>" at registration, and an old session is renamed "(old)" or archived before its
  replacement takes the name. The coordinator unbinds a PR from its
  session after merging it, so the PR's close does not auto-archive it. Structure test for
  these rules; pitfalls for nested chains and the merging coordinator's auto-archive.
- **0.4.0**: two context thresholds instead of one. Soft (default 250k): finish the current
  issue, take no new one, then rotate. Hard (default 400k, or 75% of the model's window):
  stop at the next safe point and rotate. The handover is written before the session's last
  PR merges. `check-context.sh` reports `ok` / `SOFT` / `HARD` (was `ok` / `ROTATE`) and
  takes `--soft`, `--hard`, `--window` (a small window caps soft at 50%, hard at 75%).
  `per-issue` sessions write no handover file; at hard they write it into the PR. Pitfalls for subagents and the edit guard, and for
  stacked PRs without CI.
- **0.3.0**: plain language first. Procedures live in the skill; commands are shortcuts. The
  skill routes what the owner says to a procedure and lists the points where a human is
  needed. SessionStart recognises a ledger folder and a unit checkout without registration.
- **0.2.0**: core principles plus a per-project profile replace the fixed "lanes + Platform +
  QA" shape, which is now one starting point with its rules in the `saas-multitenant` pack.
  Standard ledger layout with one home per fact; `adopt` and `audit` commands; ledger lint;
  pre-push guard; edit guard for several units; per-issue sessions; integration limits and
  verification debt.
- **0.1.0**: first version, for one repo created from `agent-project-template`.
