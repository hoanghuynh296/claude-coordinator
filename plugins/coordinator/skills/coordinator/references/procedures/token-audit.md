# Procedure: Token audit (measure, then improve)

`<plugin>` and `<session>` are given in the skill's SKILL.md ("Paths").

Find out what the project's sessions spend tokens on, and turn what you find into rules:
general ones into the coordinator plugin, project ones into the profile. Run it at every
release or milestone close, or when the owner asks ("tốn token", "tối ưu token", "why is this
so expensive?").

1. **Measure.** Run
   `python3 -I <plugin>/scripts/token-report.py <transcript dir or session .jsonl> --top 12`
   for this coordinator session (its transcript and `<session>/subagents/`) and for each
   agent session of the period. The transcript directory is the Claude Code project folder
   of the working directory (`~/.claude/projects/<slug>/`). Keep the output summary only.
2. **Read the numbers.** Share per session (coordinator vs builders vs reviewers); calls per
   session and context size (cache reads); cache rewrites (`cache_write` far above the
   others means a resumed or idle session); tool calls by tool (`Poll`, `Bash`, `Read`); the
   largest tool results (screenshots, logs, dumps).
3. **Find the causes.** For each top item ask: was it a round-trip that one call could have
   done, an output that should have been a summary, a wait past the cache, a rediscovery the
   brief could have prevented, a blocked or repeated run, mechanical work done by hand, or a
   task on a bigger model than it needed. Check `references/token-economy.md` first: a cause
   it already covers means the rule was not followed (fix the brief or the procedure that let
   it happen), not that a new rule is needed.
4. **Sort the fixes.**
   - **General** (true for any project, any stack): a rule or a procedure step in the plugin.
     Open a PR on the plugin repo (`references/token-economy.md`, the procedure or template it
     belongs to, a script or a guard when a machine can enforce it; README "Unreleased").
   - **Project** (this stack, these tests, these tools, these numbers): the profile, section 8
     "Token economy" (models per task type, local test commands, the "Known" list for briefs),
     with a DECISIONS row. Update the unit brief files the ledger keeps.
5. **Report to the owner** in at most 10 lines: the top three costs with their share, the
   general rules added (plugin PR link), the project rules added, and the expected saving.
   Anything that changes models or spending is the owner's decision: ask before applying it.
6. Lint, commit and push the ledger.
