# Pitfalls (each one happened)

Read before starting a stretch of work. Each entry: what went wrong, then the fix.

## State

1. **The ledger became a log.** It was meant to hold live state; after four days it was 231
   lines of per-PR history, with tables two days stale. → Live state only, a size budget,
   `ledger-lint.sh` before every commit. History is in git.
2. **A stale delegation stayed in the ledger.** "The owner is asleep and delegated all
   decisions" was still there days later; a new coordinator could read it as valid. → Every
   delegation carries its date and is deleted when the session ends.
3. **One rule, three copies, three values.** The rotation threshold was 250k in the ledger and
   300k in memory; the model of one agent differed between two lines of the same file. → Each
   rule is written once, in `PROFILE.md`; other files point to it.
4. **Decisions with no home.** Decision ids were cited in code and docs of three repos but
   defined only in a ledger that deletes finished items. → `DECISIONS.md` is append-only, and
   each bound unit carries a one-line entry with the same id.
5. **Machine-specific notes in a portable ledger.** Session ids and home paths of an old
   machine survived a move; the memory copy drifted because its files held absolute paths.
   → Nothing machine-specific in the ledger; sessions are found by name; the lint rejects home
   paths and session ids.
6. **Repo knowledge in handover notes.** Traps about a repo's code lived in the coordinator's
   handover file, where the next agent of that repo would not see them. → Knowledge goes into
   the unit's docs in the PR that found it; a handover carries only what is in flight.
7. **A plan file nobody ticked.** A phase was shipped and released while the plan still showed
   it as not started. → Updating the plan or roadmap is part of the definition of done.

## Flow

8. **Agents faster than verification.** About 130 PRs merged in four days with one reviewer;
   the integration branch ran 35 commits ahead of the release without a browser check. → An
   integration limit per unit; at the limit, verify and release before new features.
9. **No ordered backlog.** The next task lived in the coordinator's head, so agents idled and
   the owner had to ask why. → `ROADMAP.md` lists the next issues per unit; hand out two or
   three at once.
10. **Pushes onto a merged PR's branch.** Three times an agent added commits to a branch whose
    PR had already merged; the commits went nowhere. → Delete branches on merge (repo
    setting) and install the pre-push guard (`install-guards.sh`).
11. **Stacked PRs merged into their base lose work.** → Retarget a stacked PR to the
    integration branch before merging its base.
12. **Stacked PRs got no CI.** The workflow ran only for PRs into the integration branch, so a
    PR stacked on another branch merged with no checks at all. → Merge stacks bottom-up; retarget
    each PR to the integration branch (CI then runs) before merging it.
13. **Shared-file conflicts.** Several tickets each touched CI or the build file; every merge
    conflicted. → A Platform unit owns shared and root files (switch the role on when this
    starts to happen).
14. **A release without a tag.** A release workflow tagged only PRs from `release/*`; a PR
    from the integration branch straight to main merged untagged. → The profile states exactly
    what a release is; `milestone-close` follows the profile, not habit.

## Verification

15. **"CI green" covered less than it sounded.** CI ran one language's unit tests; the web
    checks and the engine tests ran only locally. → The profile's gate names the exact
    commands; the review checks the evidence for each, and says `UNVERIFIED` for the rest.
16. **The Reviewer catches what tests miss.** It found two high-severity auth bugs that CI and
    the author's 53 tests missed. → The profile lists the risk areas where it is mandatory.
17. **Unverified claims piling up.** "JSON shape unverified", "not checked on real hardware"
    sat in notes for days. → A verification debt list in `ROADMAP.md`, cleared at release.
18. **An output difference that was not a bug.** Two days went into a mismatch that came from
    the engine seeding a random generator. → Before debugging a difference, compare the
    reference against itself.

## Sessions and tokens

19. **Messages that wake sessions.** Every cross-session message makes the receiver re-read
    its whole context. Idle notices and acks multiplied turns. → No acks, no pings, no idle
    subscriptions; one batched message per agent per round.
20. **Sessions cannot be started from Remote Control**, and only in a turn the owner started.
    → Start every session a stretch needs in one owner turn; otherwise fall back to background
    subagents with the same brief.
21. **Usage limits stop every agent at once.** → The ledger always says who is doing what;
    after the reset, continue standing agents with one message each.
22. **Unpushed worktrees get cleaned up.** A worktree with no pushed commits was removed
    during a pause and its work was lost. → Every brief: commit after each step, push after
    the first commit and after every commit.
23. **A standing agent with nothing to do.** One unit's agent was idle most of the time, yet
    kept a long context that was re-read at every message. → `per-issue` mode for units with
    intermittent work.
24. **Messaging an archived session** makes it resume with its full old context. → Archive
    after rotation; never message it again.
25. **Permission laundering.** An agent was denied an action and the coordinator did it
    instead. → What one session's permissions deny goes to the owner, not to another session.
26. **One threshold stopped agents mid-task.** At 250k a session had to hand over at once, even
    halfway through an issue; the fresh session then re-read everything, which cost more than
    it saved. → Two thresholds: soft (finish the current issue, take no new one, then
    rotate) and hard (stop at the next safe point and rotate). `check-context.sh` reports both.
27. **Handover after merge came too late.** An agent's last PR merged, the app auto-archived the
    session, and what it knew was lost before it wrote a handover. → The handover is written
    before the session's last PR merges.
28. **Subagents inherit the coordinator's edit guard.** A coordinator gave writing work to a
    subagent; the guard denied its edits too. → One-off work that writes files runs as its own session,
    not as a subagent of the coordinator.
29. **A merging coordinator was archived with its PR.** The app binds every PR a session
    touches with `gh` (create, view, review, merge), not only PRs it creates; with the setting
    "Auto-archive sessions when their pull request closes" on, it archived the session when the
    PR closed, the project had no coordinator, and the agents' reports to it failed. The first
    fix, "unbind every PR after merging it" (`mcp__ccd_pr__unbind_pr`), was not followed in
    practice: on 2026-11-16 two coordinators were archived anyway, one bound to 7 merged PRs
    it never unbound. A rule that depends on memory failed (principle 7). → The app setting
    `auto_archive_on_pr_close` is off (`coordinator-register.md` checks it), and the
    coordinator archives each `per-issue` agent's session itself after merging its PR
    (`mcp__ccd_session_mgmt__archive_session`); a hook after `gh pr merge` reminds it.
30. **Nested chains on rotation.** Each session started by another nested under it; rotations
    built chains (coordinator under coordinator, agent under replaced agent), and archiving a
    parent archived its side sessions. → All sessions are top-level peers: the starter detaches
    each one right away; a replacement is never started by the session it replaces; agents
    report by message to "Coordinator: <project>".
31. **Both sides waited after a merge.** An agent reported "PR ready, next #50" and ended its
    turn; the coordinator merged and, as the kit then said, told it nothing. Agent sessions run
    only when a message arrives, and nothing noticed the stop, so both waited. → One issue, one
    full lifecycle: the agent works one issue, reports "PR ready" and waits; in the same turn
    as the merge the coordinator sends `PR #<n> merged. Next: <issue | handover | stand by |
    done>`. The plugin's Stop hook blocks the coordinator's turn from ending until it has.
32. **Both sides waited for CI.** An agent pushed, saw CI queued on the single self-hosted
    runner and ended its turn: "I'll report once CI is green". Sessions run only when a message
    arrives; Auto-fix wakes an agent on CI failure only, so the green run woke nobody, and the
    coordinator never heard "PR ready" (SME Hub PR #69, 2026-11-17; the mirror of 31). → Agents
    report "PR ready" on push, once the local gate is green, with the head SHA and the CI state;
    they never wait for CI. The coordinator owns the CI wait: on every "PR ready" it starts
    `scripts/ci-watch.sh <owner/repo> <N> <sha>` in the background in the same turn (the
    command's exit wakes it), reviews in parallel, and merges only on CI green for the reported
    head. A hook reminds it when a "PR ready" arrives.

## Tooling

33. **`ubuntu-latest` moved** and broke a pinned tool. → Pin runner images and tool versions.
34. **Branch protection on private repos** needs a paid GitHub plan. → On GitHub's 403 the
    bootstrap script warns and continues; record the owner's choice in `DECISIONS.md`.
35. **Scripts lose their exec bit** when a tool rewrites them. → Commands call scripts with
    `bash <path>`; `tests/exec-bits-test.sh` checks the mode in git.
36. **Template placeholders left behind** in CI files matched nothing. → The bootstrap script
    fails while any placeholder remains.
33. **Per-issue sessions drifting into standing ones, or never reused.** `archive_session` was
    refused in all six projects and session starts are refused while the owner is on Remote
    Control; one project let finished agents take the next issue by a vague rule and sessions
    silently became `standing`. A fresh session also re-reads every doc for a small issue. →
    One strict form: `PR #<n> merged. Next: #<m> (same session)`, sent only when `#m` is in the
    same unit, measured context is under 50% of soft, `#m` is not in a Reviewer-mandatory risk
    area, and the session has done fewer than 3 issues in a row. After the 3rd issue the next one
    goes to a fresh session. The agent renames itself "Agent: <unit> #<m>" and branches fresh.
