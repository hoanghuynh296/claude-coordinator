#!/usr/bin/env bash
# PostToolUse hook for Bash. After a registered coordinator runs `gh pr merge`, remind it to
# archive the per-issue agent's session (the app setting auto_archive_on_pr_close stays off,
# so nothing else archives it). Unregistered sessions and other commands: no output.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

cmd="$(json_get "$input" tool_input.command)"
[[ "$cmd" =~ (^|[^A-Za-z0-9_-])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]] || exit 0

msg='Coordinator: a PR was merged. If its author is a per-issue agent, archive that session now (mcp__ccd_session_mgmt__archive_session, by name "Agent: <unit> #<issue>"); a standing session is archived only on rotation. Then update the ledger (review-merge.md, step 7). If the app setting auto_archive_on_pr_close is still on, unbind this PR from your session (mcp__ccd_pr__unbind_pr) and ask the owner to turn the setting off.'
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$msg")"
