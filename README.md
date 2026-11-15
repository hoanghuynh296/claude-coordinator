# claude-coordinator

A Claude Code plugin marketplace with one plugin, **`coordinator`**: run a software project with
parallel Claude sessions. A human **owner** approves the plan and makes real decisions; a
**coordinator** session plans, tickets, reviews, merges and releases but never writes product
code; long-lived **lane** sessions own directories; a **Platform** lane owns CI and shared files;
a **QA** session per milestone owns acceptance; a read-only **Reviewer** subagent checks large
or sensitive PRs.

## Install

```text
/plugin marketplace add hoanghuynh296/claude-coordinator
/plugin install coordinator@coordinator-marketplace
```

The repo is private: your `gh`/git credentials must have access. Restart the session (or run
`/reload-plugins`) after installing. Requirements: `gh` (authenticated), `git`, `python3`; `jq`
is used when present.

## New project: owner's steps

1. Open a session in the desktop app (model Opus) in an empty working folder; name it "Coordinator".
2. Run `/coordinator:kickoff` and answer the five questions in one reply.
3. Read the draft `PLAN.md` it shows you. Approve or ask for changes. Nothing is created before
   you approve.
4. The coordinator runs `scripts/bootstrap.sh`: repo from
   [`hoanghuynh296/agent-project-template`](https://github.com/hoanghuynh296/agent-project-template),
   placeholders filled (including CI), `TEMPLATE.md` removed, `develop` as default branch,
   delete-branch-on-merge, labels and milestones, private `<repo>-coordination` ledger repo,
   branch protection with required checks. It then registers itself as coordinator.
5. Do the owner-side tasks it lists (accounts, domains, secrets, billing).
6. Say "start M0" (or run `/coordinator:milestone-start M0`) **from the desktop app**: all lane,
   Platform and QA sessions for the milestone are started in that one turn, because sessions can
   only be started from your own message. On Remote Control the coordinator falls back to
   subagents and converts them to sessions when you are back.
7. From then on: answer decisions when asked, test the demo at milestone close, merge the release
   PR (`release/*` -> `main`; the tag is created automatically).

## Commands

| Command | What it does |
|---|---|
| `/coordinator:kickoff` | interview -> draft `docs/PLAN.md` -> owner approval -> bootstrap -> register |
| `/coordinator:coordinator-register <ledger> [project]` | register this session as coordinator of an existing project |
| `/coordinator:milestone-start <Mn>` | Issues per ticket, contract first, start lane + Platform + QA sessions in this turn |
| `/coordinator:ticket <lane> <goal>` | one Issue from the ticket form fields |
| `/coordinator:review-merge <PR>` | CI + scope check, Reviewer when required, squash-merge into `develop`, ledger update |
| `/coordinator:milestone-close <Mn> [version]` | QA verdict on staging, demo instructions, release PR from `release/*`, tag |
| `/coordinator:handover [session]` | handover note into the ledger, rotation proposal |
| `/coordinator:status` | concise status from the ledger + GitHub |

Also included: the `coordinator` skill (method, templates, review checklist, pitfalls), agents
`coordinator:reviewer` (Opus, read-only) and `coordinator:oneoff-builder` (Sonnet, worktree,
pushes its own branch and opens a PR), and scripts `bootstrap.sh`, `register.sh`,
`check-context.sh` (context size per session from its transcript; flags ~250k for rotation).

## How the guard works

`/coordinator:kickoff` and `/coordinator:coordinator-register` write
`~/.claude/coordinator/sessions/<session_id>` with the ledger path (and project path). Two hooks
read it:

- **PreToolUse** on `Edit|Write|MultiEdit|NotebookEdit`: in a registered session, an edit is
  denied unless the path is in the ledger repo, `docs/PLAN.md`, `docs/adr/**`,
  `docs/contracts/README.md` or `AGENTS.md` of the project, `~/.claude/**`, the session
  scratchpad, or a temp dir. The deny message tells the coordinator to delegate (ticket, lane,
  Platform or one-off subagent). Unregistered sessions are never affected.
- **SessionStart**: in a registered session, prints the ledger path and a reminder (read
  `COORDINATION.md` first; rotate at ~250k).

Limitations: only the edit tools are guarded; a Bash redirection (`>`, `sed -i`, `tee`) is not
blocked. `AGENTS.md` is allowed as a whole although section 7 belongs to Platform. A forked
session gets a new session id and must register again; unregister with
`scripts/register.sh --unregister <session_id>`.

## Adopting in an existing project

1. Install the plugin, open the coordinator session in the project.
2. No ledger repo yet: ask the coordinator to create one
   (`bootstrap.sh <owner/repo> <project-dir> --ledger-only` creates `<repo>-coordination` with
   `COORDINATION.md` and `handover/`, nothing else).
3. Run `/coordinator:coordinator-register <ledger-dir> <project-dir>`.
4. Make sure the project has `OWNERSHIP.md`, `AGENTS.md`, a ticket Issue form and a release
   workflow for `release/*` branches; copy them from the template if not (via a Platform ticket).

## Layout

```text
.claude-plugin/marketplace.json
plugins/coordinator/
  .claude-plugin/plugin.json
  skills/coordinator/SKILL.md, references/{roles,workflow,review-checklist,pitfalls}.md, references/templates/*.md
  commands/*.md
  agents/{reviewer,oneoff-builder}.md
  hooks/hooks.json, hooks/{lib,coordinator-guard,session-start}.sh
  scripts/{bootstrap,register,check-context}.sh
tests/hooks-test.sh
```

Run `bash tests/hooks-test.sh` to test the hooks with sample inputs.
