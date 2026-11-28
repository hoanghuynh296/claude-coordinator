#!/usr/bin/env bash
# PostToolUse hook for SendMessage / mcp__ccd_session_mgmt__send_message (Antigravity:
# send_message / swarm). Records an agent's reports for report-guard.sh: when a session that is
# not a registered coordinator sends a message whose first non-empty line starts with
# `PR ready:`, `blocked:`, `Draft ready:` or names a handover, one line is appended to
# $COORD_HOME/state/<session>/reports: "<epoch> <kind> <hex words of the message>"
# (kind: ready | blocked | draft | handover). Whoever the recipient is. No output (Antigravity: {}).
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
ag=0; is_antigravity "$input" && ag=1
silent() { (( ag )) && printf '{}\n'; exit 0; }
sid="$(hook_sid "$input")" || silent
registration_file "$sid" >/dev/null && silent

text="$(json_get "$input" tool_input.message)"
[[ -z "$text" ]] && text="$(json_get "$input" toolCall.args.Message)"
[[ -z "$text" ]] && text="$(json_get "$input" toolCall.args.brief)"
[[ -n "$text" ]] || silent
first="$(printf '%s\n' "$text" | awk 'NF {print; exit}' | sed 's/^[[:space:]]*//')"
case "$first" in
  "PR ready:"*) kind=ready ;;
  [Bb]locked:*) kind=blocked ;;
  "Draft ready:"*) kind=draft ;;
  *[Hh]andover*) kind=handover ;;
  *) silent ;;
esac
shas="$(printf '%s' "$text" | tr -c '0-9a-fA-F' '\n' | awk 'length($0) >= 7 && length($0) <= 40' \
  | tr 'A-F' 'a-f' | sort -u | head -n 20 | paste -sd ' ' -)"
d="$(state_dir "$sid")" || silent
printf '%s %s %s\n' "$(date +%s)" "$kind" "$shas" >>"$d/reports"
rm -f "$d/report-blocks"
silent
