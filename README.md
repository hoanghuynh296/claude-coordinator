# claude-coordinator

A Claude Code plugin marketplace with one plugin, **`coordinator`**: a reusable way to run a
software project with several Claude sessions, whatever the project's shape.

It has two layers:

- **Core principles**, the same for every project: one owner and one coordinator; state in
  files, not in sessions; work as issues with acceptance criteria; units that own their ground
  and meet at versioned contracts; independent review with evidence; bounded integration;
  machine-enforced rules; lean messaging.
- **A project profile** (`coordination/PROFILE.md` in the project's ledger repo): how this
  project applies them. Nothing about the shape is assumed by the commands.

| The profile chooses | Examples |
|---|---|
| Topology | one repo split into lanes · several repos that feed each other · a mix |
| Units and how they are staffed | a standing session per unit · a fresh session per issue |
| Optional roles | Platform (shared files), QA (acceptance per milestone), Reviewer, one-off builder |
| Flow | integration and release branches, merge method, what a release is, milestones or a continuous backlog |
| Gates and limits | the exact command that must be green; how far integration may run ahead of a release |
| Authority | who releases each unit; what only the owner decides |
| Packs | `saas-multitenant`, `artifact-contracts`, `ui-product` |

Starting points for common shapes (a SaaS monorepo, a family of repos, one small repo, a
knowledge base, a library) are in the skill's `references/profile.md`.

## Install

```text
/plugin marketplace add hoanghuynh296/claude-coordinator
/plugin install coordinator@coordinator-marketplace
```

The repo is private: your `gh` and git credentials must have access. Restart the session (or
run `/reload-plugins`) after installing. Requirements: `gh` (authenticated), `git`, `python3`;
`jq` is used when present.

## New project: the owner's steps

1. Open a session in the desktop app in an empty working folder; name it "Coordinator: <project>".
2. Run `/coordinator:kickoff` and answer its questions in one reply.
3. Read the draft plan and the draft profile. Approve or ask for changes. Nothing is created
   before you approve.
4. The coordinator creates the ledger, the repos the profile lists, labels and guards, and
   registers itself.
5. Do the owner-side tasks it lists (accounts, secrets, billing).
6. Say "start" from the desktop app: sessions can only be started from your own message.
7. From then on: answer decisions when asked, and release the units your profile gives you.

## Existing project

Run `/coordinator:adopt`. The coordinator reads how the project works today, proposes a
profile that matches it plus the changes it recommends, waits for your approval, then creates
the ledger or migrates an existing one into the standard layout.

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

## Commands

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
| `/coordinator:audit` | ledger lint, drift against GitHub, integration limits, idle units, stale delegations |

Also included: the `coordinator` skill (principles, profile guide, workflow, roles, state
files, review checklist, pitfalls, packs, templates) and two agents: `coordinator:reviewer`
(read-only) and `coordinator:oneoff-builder` (own worktree, own branch, own PR).

## Mechanical guards

| Guard | What it stops |
|---|---|
| Edit guard (PreToolUse hook) | a registered coordinator editing anything inside a unit except the planning files the profile allows. Understands several units, also when they sit inside the ledger folder. `register.sh --allow <glob>` sets the allowed files; `--no-guard` switches it off for projects whose profile lets the coordinator write code |
| `scripts/ledger-lint.sh <ledger>` | a ledger out of shape: missing files, over the size budget, session ids or home paths, decision ids cited but not defined, leftover placeholders. Warns on a stale date, on history in the live ledger, on an undated delegation |
| `scripts/pre-push-guard.sh` (git pre-push hook) | pushing to a branch whose pull request is already merged or closed; optional local protection of release branches |
| `scripts/install-guards.sh [--settings] <repo>...` | installs the pre-push guard in each clone; `--settings` turns on delete-branch-on-merge on GitHub |

Limits: the edit guard covers the edit tools only; a shell redirection is not blocked. The
pre-push guard fails open when `gh` cannot reach the repo. A forked session gets a new session
id and must register again.

## Scripts

| Script | Purpose |
|---|---|
| `init-ledger.sh <dir> [--name] [--owner] [--workspace]` | write the standard ledger layout from the templates; never overwrites |
| `ledger-lint.sh [dir]` | see above; budgets in the environment or in `<dir>/.ledger-lint` |
| `install-guards.sh`, `pre-push-guard.sh` | see above |
| `register.sh <session> <ledger> [unit...] [--allow glob]... [--allow-none] [--no-guard]` | register or `--unregister` a coordinator session |
| `check-context.sh [session...]` | context size per session from its transcript; flags the rotation threshold (`ROTATE_AT`, default 250000) |
| `bootstrap.sh <owner/repo> <dir> ...` | the single-repo SaaS starting point: repo from `hoanghuynh296/agent-project-template`, placeholders, `develop`, labels, ledger, branch protection. `--ledger-only` creates just the ledger; `--dry-run` prints every action |

## Layout

```text
.claude-plugin/marketplace.json
plugins/coordinator/
  .claude-plugin/plugin.json
  skills/coordinator/SKILL.md
  skills/coordinator/references/{principles,profile,workflow,roles,state-files,review-checklist,pitfalls}.md
  skills/coordinator/references/packs/{saas-multitenant,artifact-contracts,ui-product}.md
  skills/coordinator/references/templates/*.md
  commands/*.md
  agents/{reviewer,oneoff-builder}.md
  hooks/hooks.json, hooks/{lib,coordinator-guard,session-start}.sh
  scripts/{init-ledger,ledger-lint,install-guards,pre-push-guard,register,check-context,bootstrap}.sh
tests/{hooks,ledger-lint,pre-push-guard,bootstrap,exec-bits}-test.sh
```

## Tests

```sh
bash tests/hooks-test.sh           # edit guard and SessionStart, jq and python3 paths, multi-unit workspace
bash tests/ledger-lint-test.sh     # every lint rule; a fresh ledger passes
bash tests/pre-push-guard-test.sh  # merged, closed and open PRs with a fake gh; install-guards
bash tests/bootstrap-test.sh [template-dir]   # full bootstrap against local bare repos and a fake gh
bash tests/exec-bits-test.sh       # every plugin *.sh is executable in git
```

## Changes

- **0.2.0**: core principles plus a per-project profile replace the fixed "lanes + Platform +
  QA" shape, which is now one starting point with its rules in the `saas-multitenant` pack.
  Standard ledger layout with one home per fact; `adopt` and `audit` commands; ledger lint;
  pre-push guard; edit guard for several units; per-issue sessions; integration limits and
  verification debt.
- **0.1.0**: first version, for one repo created from `agent-project-template`.
