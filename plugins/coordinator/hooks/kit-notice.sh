#!/usr/bin/env bash
# Kit notice (#54). UserPromptSubmit (Claude Code) / PreInvocation via ag-chain.sh (Antigravity).
# In a session the SessionStart hook spoke to (it recorded the kit version the session runs),
# when a newer kit is installed for this runtime: one line, once per newer version,
#   "Coordinator kit <v> runs here; <new> is installed: rotate this session at the next safe point (...)"
# Everything else, and any error: no output (Antigravity: {}). No network; a session SessionStart
# did not record costs one file test.
set -u
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
input="$(cat)"
ag=0; is_antigravity "$input" && ag=1
silent() { (( ag )) && printf '{}\n'; exit 0; }
sid="$(hook_sid "$input")" || silent
line="$(kit_notice "$sid" "$( (( ag )) && echo ag)" 2>/dev/null || true)"
[[ -n "$line" ]] || silent
if (( ag )); then
  printf '{"injectSteps":[{"systemMessage":{"systemMessage":%s}}]}\n' "$(json_string "$line")"
else
  printf '%s\n' "$line"
fi
