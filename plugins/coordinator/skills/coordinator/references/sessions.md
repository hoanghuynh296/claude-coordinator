# Sessions and messages

The one home for how the project's sessions are started, placed, named, messaged, rotated and
archived, and when a task goes to a subagent instead (delegation split). Other files link here
instead of restating it. The same-session next issue and the
merge notice's form live in `procedures/review-merge.md` step 9 (coordinator) and
`templates/unit-brief.md` rule 11 (agent).

## Placement and names

- **All sessions are top-level peers.** Every session of the project sits at the top level of
  the sidebar; none nests under another. Whoever starts a session (the coordinator starting an
  agent or its own replacement) detaches it to the top level right away
  (`mcp__ccd_session_mgmt__detach_session`, the sidebar's "Detach to top level"). Nested
  sessions build a chain on every rotation, and archiving a parent archives everything under it.
  Start each agent in its own worktree: a side session that shares another's worktree cannot be
  detached. A session the starter could not detach detaches itself (`detach_session` with
  `self`); if that is refused too, ask the owner to drag it out. A session nested under you
  that you started: detach it.
- A detached agent sends no turn-end note to the coordinator, so it reports by message
  (below).
- A replacement is never started by the session it replaces. An agent's replacement is started
  by the coordinator; a coordinator's by the old coordinator (then detached) or by the owner
  from the sidebar.
- Reports go by name, so a name belongs to one live session. Before a replacement takes it,
  rename the old session "<name> (old)" or archive it. A coordinator names itself
  "Coordinator: <project>" when it registers (`procedures/coordinator-register.md`). A new
  coordinator sends every live agent one message with its name, so their reports reach it.
- Sessions are found by name ("Agent: <unit>", per-issue "Agent: <unit> #<issue>"), never by
  id. Ids do not go into the ledger.

## Archiving

- The app binds every PR a session touches with `gh` (create, view, review, merge), and with
  its setting `auto_archive_on_pr_close` on it archives the session when that PR closes. The
  setting stays off for every project run with this kit (`coordinator-register.md` checks it).
  Sessions are then archived by the coordinator: after merging a `per-issue` agent's PR, it
  archives that agent's session; a `standing` session is archived only when it is replaced.
  Fallback while the setting is still on: after each merge, `mcp__ccd_pr__get_status` and
  `mcp__ccd_pr__unbind_pr` for any PR bound to you.
- **Archive procedure** (used wherever this kit says "archive"): call
  `mcp__ccd_session_mgmt__archive_session` alone in its own message, never in parallel with
  other calls (the app's hook rewrites its input, which voids auto mode's verdict on every call
  sent with it); if it is refused with a rewritten input (the app's
  hook rewrites it, and auto mode then refuses the first call), call once more with exactly that
  input; if it is still refused, rename the session "<name> (old)" (`set_session_title`) and add
  it to ONE owner-queue line "Archive finished sessions: <names>" (one line for all, never one
  item each). `audit` checks that line. Never message an archived session. Antigravity:
  `swarm(action="kill")`, unchanged.

## Messages

- No ack-only or status-ping messages, either way. An agent is either working on the issue it
  was given or waiting on the coordinator: after "PR ready" it waits for your findings or for
  the merge notice (`review-merge.md` step 9). It never starts a next issue on its own, so a
  merge without that message leaves it idle for good.
- One batched message per agent per round: findings or answers, or the merge notice with the
  next step, sent once.
- Every agent report ends with `Context: <k tokens>`. Reports within the profile's length. Your
  own status to the owner: short, decisions first.
- Agents report by message to the coordinator session by name ("Coordinator: <project>"), for
  every outcome: PR ready, blocked or decision needed, handover written. Sessions are top-level
  peers, so no turn-end note reaches the coordinator; a report not sent as a message is lost.
- Agents do their own git plumbing (branch, push, PR, worktree clean-up).
- Never subscribe to idle notices.

## Subagent or session (delegation split)

The coordinator gives each task to a background `oneoff-builder` subagent or to an agent
session by this default split; it does not pick case by case. Both cost about the same per
task (measured 2026-11-22..28: 5.4M tokens per subagent task, 5.3M per session PR); sessions
add start and archive friction and wake the coordinator with messages, subagents cannot be
opened or steered by the owner and end with the coordinator's session.

- **Subagent:** self-contained one-round work (docs, fixtures, investigations, audits, version
  bumps, codemods, small fixes), outside every Reviewer-mandatory risk area (profile section
  6), expected under about 150k context; and any brief while sessions cannot be started
  (below).
- **Session:** product feature issues, work in a risk area, `Draft: required` UI work, work
  likely to need review rounds, work longer than the coordinator's own session will last.
- **Override per unit:** the profile may change the split for a unit with one line, in the
  unit table's Session column or in Budgets (`Delegation: <unit>: sessions only` /
  `subagent for <kinds>`). The profile line wins over this default.
- **Too large for a subagent:** a builder that finds the work larger than the split allows
  (a risk area, over about 150k, needs a design decision or several rounds) stops, pushes what
  it has, opens or updates its PR and reports `blocked: needs a session` with the PR link. The
  coordinator starts a session for the issue with that PR link in its prompt (same branch).
- **Fix rounds on a subagent PR:** resume the same subagent with the findings when it still
  exists (Claude Code: `SendMessage` to its agent id; Antigravity: `send_message` to the
  subagent); otherwise a fresh `oneoff-builder` gets the PR link and the findings only, not
  the whole brief again.
- Runtimes: subagent = Agent tool `coordinator:oneoff-builder` (Claude Code) /
  `invoke_subagent(TypeName="oneoff-builder")` (Antigravity); session = start session in a
  worktree (Claude Code) / `swarm(action="add", ...)` (Antigravity). Briefs, reports and
  output contracts are the same either way.

## Staffing caps

- **Claude Code:** after each owner message the app starts at most 10 sessions without a card,
  and at most 5 agent sessions work at once; it refuses the rest. Before starting, count the
  agents already working: start at most 5 working at once and at most 10 starts per owner
  message, most urgent first. Each one over the caps gets one line under the ledger's "Pending
  starts" (`COORDINATION.md`) and starts first on the next owner turn. Subagents are not
  sessions and do not count.
- **Another repository:** an agent whose folder, host, environment or preset differs from the
  coordinator's is started only in an owner-started turn (`initiation: "user_asked"` with its
  `cwd`), never proposed as a card: a card cannot carry a host, folder, environment or preset.
  Outside such a turn it waits under "Pending starts".
- **Antigravity:** no cap; `swarm` starts every agent the stretch needs.

## When sessions cannot be started

- Sessions can only be started in a turn the owner started from the desktop app. Start every
  session the stretch needs in that one turn, within the staffing caps above.
- If sessions cannot be started (the owner is on Remote Control, the coordinator runs as a
  terminal CLI session, or the tool is unavailable), run the same brief as a background
  `oneoff-builder` subagent with its own worktree `<unit>/.claude/worktrees/builder-<name>`.
  The subagents run inside the coordinator's session and share its edit guard; on Claude Code
  the guard lets a `coordinator:oneoff-builder` write inside its own worktree (hook fields
  `agent_id` / `agent_type`), so the guard stays on. On Antigravity (its hook input names no
  subagent), or if a builder still reports a guard refusal in its worktree, re-register with
  `--no-guard` first (procedure `coordinator-register.md`), only in this case, and with the
  guard on again when sessions can be started. The coordinator itself still edits no unit
  code: it tickets, briefs, reviews and merges.
- While sessions can be started, the delegation split above decides; while they cannot, every
  brief runs as a subagent (Claude Code: guard on; `--no-guard` only where the builder's
  worktree writes are refused) and the session-side ones move to sessions at the next desktop
  turn.
- A usage limit stops every agent at once. The ledger says who was doing what.

## Context thresholds and rotation

- Two thresholds (profile "Budgets"; defaults for agents 250k soft, 400k hard; for the
  coordinator 300k soft, 450k hard on any model and window, as its context grows with every merge and message: `check-context.sh
  --profile <ledger>` applies the role's pair, `--role coordinator` forces the coordinator's;
  each line names the threshold it used). Context is measured, never self-reported: the
  rotation guard hook measures the coordinator's on every owner turn, and `review-merge.md`
  step 9 measures an agent's before its Next. Past **soft**: send no new issue; the session
  finishes its current issue (PR, gate green), writes its handover and is replaced. Past
  **hard**: it stops at the next safe point (commit, push), writes a full handover, reports
  "blocked: rotate". Never stop a session mid-task at soft: a fresh one re-reads everything.
- **The coordinator** has no current issue, so its two thresholds mean: past **soft**, rotate at
  the next owner desktop turn (handover, then a replacement); past **hard**, rotate in this
  turn. The rotation guard hook measures the coordinator's own context on every owner turn (no
  tool call): past soft each owner turn gets one line `Coordinator at <k>k / soft <s>k: rotate
  now (...)`; past hard the Stop hook blocks the end of an owner-started turn until
  `coordination/handover/coordinator.md` is committed in this session (a merge in flight is let
  through once). Never rotate while a background subagent still runs: wait for its report, or
  write it into the handover as "running: <agent>, <task>". On Remote Control (no session can
  be started) the handover is still due, and the rotation also becomes the first Owner queue
  item of `COORDINATION.md` so the owner starts the replacement at the next desktop turn.
- The handover is written **before** the session's last PR merges: the coordinator archives a
  `per-issue` session right after its PR merges, and its context is gone.
- `standing` session past a threshold: handover note, fresh session with the same name,
  archive the old one. `per-issue` sessions are archived by the coordinator after their PR
  merges and write no handover file: at soft they just finish the issue; at hard they write
  done, left, commands to re-run and traps into the PR (or the issue if there is no PR yet).
