#!/usr/bin/env bash
# PostToolUse hook for SendMessage and mcp__ccd_session_mgmt__send_message. When a registered
# coordinator sends a message whose text holds "PR #N merged" and a "Next:" line with content,
# PR N is no longer pending (see merge-reminder.sh). Anything else: no output, no change.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

text=""
for f in message text content prompt body; do
  v="$(json_get "$input" "tool_input.$f")"
  [[ -n "$v" ]] && text+="$v"$'\n'
done
[[ -n "$text" ]] || exit 0
[[ "$text" =~ (^|[^A-Za-z])Next:[[:space:]]*[^[:space:]] ]] || exit 0

cleared=()
rest="$text"
while [[ "$rest" =~ PR[[:space:]]+#([0-9]+)[[:space:]]+merged(.*) ]]; do
  n="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
  pending_remove "$sid" "$n" && cleared+=("#$n")
done
[[ ${#cleared[@]} -gt 0 ]] || exit 0

left="$(pending_list "$sid" | awk '{printf "#%s ", $1}')"
msg="Coordinator: Next sent for ${cleared[*]}."
[[ -n "$left" ]] && msg+=" Still pending: ${left% }."
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$msg")"
