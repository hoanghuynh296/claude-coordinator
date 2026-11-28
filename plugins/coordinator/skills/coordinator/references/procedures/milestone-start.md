# Procedure: Start a milestone or a stretch of work

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Start the named milestone or stretch of work. Reread `references/pitfalls.md`.

1. Take the content and exit criteria from `coordination/ROADMAP.md` (milestone cadence) or
   the top of each unit's backlog (continuous cadence). Split it into issues, one unit each,
   each small enough for one PR. Include:
   - the contract issue first, if the stretch adds or changes an interface between units;
   - a QA issue (acceptance tests from the exit criteria) when the profile has QA on;
   - Platform issues for shared or root files when the profile has Platform on.
2. Create each issue with the `ticket` procedure. Issues that depend on the contract say
   "depends on #<n>" and are not handed out until it merges.
3. Order each unit's list in `ROADMAP.md`. Update `COORDINATION.md` (in progress per unit).
   Commit the ledger (`ledger-commit.sh`).
4. **Staff it now, in this turn** (sessions can only be started from the owner's own message),
   within the staffing caps (`references/sessions.md`, "Staffing caps": at most 5 agents
   working at once and 10 starts per owner message on Claude Code; the rest go to "Pending
   starts" and start on the next owner turn; another repo's agent only as `user_asked`, never
   a card):
   - Split first: per issue, subagent or session by the delegation split
     (`references/sessions.md`, "Subagent or session"; the profile's `Delegation:` line wins).
     Self-contained one-round work outside the risk areas, under about 150k: a background
     `oneoff-builder` (own worktree `<unit>/.claude/worktrees/builder-<name>`); feature issues,
     risk areas, `Draft: required` UI and multi-round work: a session, as below.
   - `standing` units with a live session: one message with its next ONE issue, if it is
     standing by. An agent with a PR in review gets its next issue in the merge notice
     (`PR #<n> merged. Next: #<m>`, `review-merge.md` step 9), not before.
   - `standing` units without a session, and `per-issue` units: start a fresh session, named
     per the profile, with the profile's model and effort for this runtime, background from
     `references/templates/unit-brief.md` (plus `platform-brief.md` / `qa-brief.md`), prompt =
     the link of its one issue. Start each in its own worktree and detach it to the top level right away
     (`mcp__ccd_session_mgmt__detach_session`); if that is refused, the brief tells the agent
     to detach itself, and otherwise ask the owner to drag it out. The brief names
     "Coordinator: <project>" as the session it reports to by message.
   - Cannot start sessions (owner on Remote Control, the coordinator runs as a terminal CLI
     session, or the tool is unavailable): launch the same briefs as background
     `oneoff-builder` subagents, each with its own worktree `<unit>/.claude/worktrees/builder-<name>`
     (the guard lets a builder write there on Claude Code; on Antigravity re-register this
     session with `--no-guard` first, its hook input names no subagent). The coordinator
     still writes no unit code. Convert to sessions (and, after `--no-guard`, re-register with
     the guard on) when the owner is back at the desktop.
5. Reply to the owner in at most 8 lines: issues created (numbers), who is doing what, what
   waits on the contract, any owner-side task this stretch needs.
