#!/usr/bin/env bash
# PostToolUse hook for Bash. After a registered coordinator merges a PR with `gh pr merge <N>`:
#   - records N as "pending Next" in the session's state dir (lib.sh, state_dir); the Stop hook
#     (next-guard.sh) blocks the end of the turn until the author got "PR #N merged. Next: ..."
#     (cleared by next-sent.sh) or the coordinator cleared N with scripts/next-clear.sh;
#   - reminds it to send that message and to archive a per-issue agent's session.
# Unregistered sessions and other commands: no output, no state.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

cmd="$(json_get "$input" tool_input.command)"
merge_re='(^|[^A-Za-z0-9_-])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)(.*)'
[[ "$cmd" =~ $merge_re ]] || exit 0

# A failed command: Claude Code reports it as a tool error (no PostToolUse), but be safe.
interrupted="$(json_get "$input" tool_response.interrupted)"
[[ "$interrupted" == "true" ]] && exit 0
out="$(json_get "$input" tool_response.stdout) $(json_get "$input" tool_response.stderr)"
case "$out" in
  *"GraphQL:"*|*"not mergeable"*|*"X Pull request"*|*"failed to merge"*|*"Exit code "[1-9]*) exit 0 ;;
esac

# Every `gh pr merge` in the command: PR number (N, #N or a .../pull/N URL) and --repo.
recorded=(); unparsed=0; auto=0
rest="${cmd//$'\n'/;}"
while [[ "$rest" =~ $merge_re ]]; do
  rest="${BASH_REMATCH[3]}"
  seg="${rest%%[;&|]*}"
  read -r -a toks <<<"$seg" || true
  pr=""; repo=""; skip=""; seg_auto=0
  for tok in ${toks[@]+"${toks[@]}"}; do
    tok="${tok%\"}"; tok="${tok#\"}"; tok="${tok%\'}"; tok="${tok#\'}"
    if [[ -n "$skip" ]]; then [[ "$skip" == repo ]] && repo="$tok"; skip=""; continue; fi
    case "$tok" in
      --repo=*) repo="${tok#--repo=}" ;;
      -R|--repo) skip=repo ;;
      -t|--subject|-b|--body|-F|--body-file|-A|--author-email|--match-head-commit) skip=1 ;;
      --auto) seg_auto=1; auto=1 ;;
      -*) ;;
      *) [[ -z "$pr" ]] && pr="$tok" ;;
    esac
  done
  if [[ "$pr" =~ ^#?([0-9]+)$ ]]; then
    pr="${BASH_REMATCH[1]}"
  elif [[ "$pr" =~ ^https?://[^/]+/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
    [[ -z "$repo" ]] && repo="${BASH_REMATCH[1]}"; pr="${BASH_REMATCH[2]}"
  else
    unparsed=1; continue
  fi
  [[ $seg_auto -eq 1 ]] && continue   # --auto: queued, not merged yet
  pending_add "$sid" "$pr" "$repo" && recorded+=("$pr")
done

if [[ ${#recorded[@]} -gt 0 ]]; then
  list=""; for n in "${recorded[@]}"; do list+="#$n, "; done; list="${list%, }"
  first="${recorded[0]}"
  msg="Coordinator: merged ${list}. Pending until sent: in THIS turn, read the author's context (mcp__ccd_session_mgmt__get_usage) and send the author one message \"PR #${first} merged. Next: <issue | handover | stand by | done>\" (at or past the soft limit: handover; a per-issue agent: done). The agent waits after \"PR ready\" and runs only when a message arrives; the Stop hook blocks your turn until it is sent. Then, for a per-issue agent, archive its session (mcp__ccd_session_mgmt__archive_session, name \"Agent: <unit> #<issue>\"); a standing session is archived only on rotation. Update the ledger (review-merge.md, steps 7 and 9). If the author can no longer receive a message: bash \"${plugin}/scripts/next-clear.sh\" ${sid} <N> \"<reason>\". If the app setting auto_archive_on_pr_close is still on, unbind this PR from your session (mcp__ccd_pr__unbind_pr) and ask the owner to turn the setting off."
elif [[ $auto -eq 1 ]]; then
  msg="Coordinator: gh pr merge --auto only queues the merge. Once it has merged, send the author \"PR #<N> merged. Next: <issue | handover | stand by | done>\" (review-merge.md, step 9)."
else
  msg="Coordinator: a PR was merged, but its number could not be read from the command (pass the number to gh pr merge). Send its author \"PR #<N> merged. Next: <issue | handover | stand by | done>\" in this turn (review-merge.md, step 9); if it is a per-issue agent, archive its session afterwards (mcp__ccd_session_mgmt__archive_session); a standing session is archived only on rotation."
fi
[[ $unparsed -eq 1 && ${#recorded[@]} -gt 0 ]] && msg+=" One more merge in this command had no readable PR number: send its Next message too."
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$msg")"
