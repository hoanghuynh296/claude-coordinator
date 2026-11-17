#!/usr/bin/env bash
# UserPromptSubmit hook, and PostToolUse hook for the inbox tools (ReadNotifications,
# FetchInboxMessage). When a registered coordinator receives a text that says "PR ready", it is
# reminded to start the background CI watch in this turn (review-merge.md, step 2): agents
# report on push, and a green CI run wakes nobody, so the watch's exit is what brings the
# coordinator back when CI ends. A reminder only, never a block: how an agent's message reaches
# the coordinator depends on the host, so the procedure is the rule and this hook a nudge.
# PR links (github.com/<owner>/<repo>/pull/<N>) in the text become ready-to-run commands.
# Unregistered sessions and other texts: no output.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

event="$(json_get "$input" hook_event_name)"
if [[ "$event" == "UserPromptSubmit" ]]; then
  text="$(json_get "$input" prompt)"
else
  event="PostToolUse"
  text="$(json_get "$input" tool_response)"
fi
shopt -s nocasematch
[[ "$text" =~ PR[[:space:]]+(is[[:space:]]+)?ready ]] || exit 0
shopt -u nocasematch

cmds=(); rest="$text"
re='github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)(.*)'
while [[ "$rest" =~ $re ]]; do
  c="bash \"$plugin/scripts/ci-watch.sh\" ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} <head sha>"
  rest="${BASH_REMATCH[3]}"
  [[ " ${cmds[*]-} " == *"$c"* ]] || cmds+=("$c")
done

msg="Coordinator: an agent reported \"PR ready\". In THIS turn start the CI watch in the background (Bash with run_in_background), with the head SHA from the report: bash \"$plugin/scripts/ci-watch.sh\" <owner/repo> <N> <head sha>. Its exit wakes you when CI ends (green, red or stale-head); a green run wakes nobody else. Review in parallel (Reviewer if the profile requires it); merge only when CI is green on the reported head and the review passed (review-merge.md, steps 2 and 6)."
[[ ${#cmds[@]} -gt 0 ]] && msg+=" For the PR(s) named: $(printf '%s; ' "${cmds[@]}")"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$event" "$(json_string "${msg%; }")"
