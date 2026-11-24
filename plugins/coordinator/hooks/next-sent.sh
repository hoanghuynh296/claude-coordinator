#!/usr/bin/env bash
# PostToolUse hook for SendMessage ({to, message, summary}) and
# mcp__ccd_session_mgmt__send_message ({session_id, message}). When a registered coordinator
# sends a message whose text holds "PR #N merged" (or "PR owner/repo#N merged") and a "Next:"
# with content, that pending PR is cleared (see merge-reminder.sh). Whoever the recipient is:
# the hook cannot tell the author's session from another, so the coordinator sends the notice
# to the author only. "Next: #M (same session)" is a valid Next like any other. A bare #N that
# is pending in two repos is not cleared; the reply says so.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(hook_sid "$input")" || exit 0
ag=0; is_antigravity "$input" && ag=1
silent() { (( ag )) && printf '{}\n'; exit 0; }
registration_file "$sid" >/dev/null || silent

text="$(json_get "$input" tool_input.message)"
[[ -z "$text" ]] && text="$(json_get "$input" toolCall.args.Message)"
[[ -z "$text" ]] && text="$(json_get "$input" toolCall.args.brief)"
[[ -n "$text" ]] || silent
[[ "$text" =~ (^|[^A-Za-z])Next:[[:space:]]*[^[:space:]] ]] || silent

cleared=(); ambiguous=()
rest="$text"
re='PR[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#([0-9]+)[[:space:]]+merged(.*)'
while [[ "$rest" =~ $re ]]; do
  ref="${BASH_REMATCH[1]}#${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
  key="$(pending_resolve "$sid" "$ref")"; rc=$?
  if [[ $rc -eq 0 ]]; then pending_remove "$sid" "$key" && cleared+=("$key")
  elif [[ $rc -eq 2 ]]; then ambiguous+=("$ref"); fi
done
[[ ${#cleared[@]} -gt 0 || ${#ambiguous[@]} -gt 0 ]] || silent

msg="Coordinator:"
[[ ${#cleared[@]} -gt 0 ]] && msg+=" Next sent for ${cleared[*]}."
[[ ${#ambiguous[@]} -gt 0 ]] && msg+=" Not cleared: ${ambiguous[*]} is pending in more than one repo; write \"PR owner/repo#N merged. Next: ...\"."
left="$(pending_keys "$sid" | tr '\n' ' ')"
[[ -n "$left" ]] && msg+=" Still pending: ${left% }."
if (( ag )); then
  printf '{}\n'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$msg")"
fi
