---
name: token-audit
description: Measure where a coordinated project's Claude sessions spend tokens (coordinator, builders, reviewers; calls, cache reads and rewrites, tool calls, largest outputs) and improve it - general rules go into the coordinator plugin, project-specific rules into the project's profile.
when_to_use: Use when the owner asks why work is expensive or slow, wants to save tokens or usage ("tốn token", "tiết kiệm token", "tối ưu token", "usage limit", "why so many tokens"), after a release or milestone close, or when a session hit a usage limit.
---

# Token audit

Follow the coordinator skill's procedure `references/procedures/token-audit.md` (in
`${CLAUDE_PLUGIN_ROOT}/skills/coordinator/`). Rules already known are in
`references/token-economy.md` there; read them first.

The measuring tool: `python3 -I ${CLAUDE_PLUGIN_ROOT}/scripts/token-report.py <transcript dir | session.jsonl> [--top N] [--json]`.
Transcripts are in `~/.claude/projects/<slug of the working directory>/`: one `<session>.jsonl`
per session, its subagents in `<session>/subagents/agent-*.jsonl` (names in `.meta.json`).

The loop, every time: **measure → find the causes → general rule into the plugin (PR) →
project rule into the profile → report to the owner.** Models and spending stay the owner's
decision.
