#!/usr/bin/env bash
# PostToolUse hook for SendMessage / mcp__ccd_session_mgmt__send_message (Antigravity:
# send_message / swarm). Records an agent's reports for report-guard.sh: when a session that is
# not a registered coordinator sends a message whose first non-empty line starts with
# `PR ready:`, `blocked:`, `Draft ready:` or `handover`, one line is appended to
# $COORD_HOME/state/<session>/reports: "<epoch> <kind> <pushed> <hex words of the message>"
#   kind    ready | blocked | draft | handover
#   pushed  the branch head as last pushed (the remote-tracking ref of the hook's cwd: @{push},
#           else refs/remotes/origin/<branch>), "-" when unknown
# Whoever the recipient is. No output (Antigravity: {}).
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
  [Hh]andover*) kind=handover ;;
  *) silent ;;
esac
shas="$(printf '%s' "$text" | tr -c '0-9a-fA-F' '\n' | awk 'length($0) >= 7 && length($0) <= 40' \
  | tr 'A-F' 'a-f' | sort -u | head -n 20 | paste -sd ' ' -)"
dir="$(json_get "$input" cwd)"; [[ -n "$dir" && -d "$dir" ]] || dir="$PWD"
pushed="$(git -C "$dir" rev-parse -q --verify '@{push}' 2>/dev/null)" || pushed=""
if [[ -z "$pushed" ]]; then
  b="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)" \
    && pushed="$(git -C "$dir" rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null)" || pushed=""
fi
[[ "$pushed" =~ ^[0-9a-f]{40}$ ]] || pushed=-
d="$(state_dir "$sid")" || silent
printf '%s %s %s %s\n' "$(date +%s)" "$kind" "$pushed" "$shas" >>"$d/reports"
rm -f "$d/report-blocks"
silent
