#!/usr/bin/env bash
# Stop hook. While a registered coordinator has merged a PR without sending its author
# "PR #N merged. Next: ..." (merge-reminder.sh records it, next-sent.sh clears it), the end of
# the turn is blocked with a reason naming each PR and the message format.
# No endless loop: at most MAX_BLOCKS (default 3, env COORDINATOR_NEXT_MAX_BLOCKS) blocks in
# one turn (counted while stop_hook_active is true); after that the stop is allowed with a
# warning, and the next turn blocks again. Unregistered sessions: no output.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# timeout_run <cmd...>: run with a 10 s cap when `timeout` exists (a hung gh must not hang Stop)
timeout_run() { if command -v timeout >/dev/null 2>&1; then timeout 10 "$@"; else "$@"; fi; }

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0
pending="$(pending_keys "$sid")"
[[ -n "$pending" ]] || exit 0

# Drop exempt PRs (release/* heads, coordinator-authored) from the pending list.
while read -r key; do
  [[ -n "$key" ]] || continue
  info="$(timeout_run "${COORDINATOR_GH:-gh}" pr view "${key##*#}" -R "${key%#*}" --json headRefName,author \
    --jq '.headRefName + " " + .author.login' 2>/dev/null)" || continue
  head="${info%% *}"; author="${info#* }"
  if [[ "$head" == release/* || "$head" == coordinator/* || \
        ( -n "${COORDINATOR_GH_LOGIN:-}" && "$author" == "$COORDINATOR_GH_LOGIN" ) ]]; then
    pending_remove "$sid" "$key" || true
  fi
done <<<"$pending"
pending="$(pending_keys "$sid")"
[[ -n "$pending" ]] || exit 0

d="$(state_dir "$sid")" || exit 0
max="${COORDINATOR_NEXT_MAX_BLOCKS:-3}"
[[ "$max" =~ ^[0-9]+$ ]] || max=3
active="$(json_get "$input" stop_hook_active)"
count=0
if [[ "$active" == "true" && -f "$d/stop-blocks" ]]; then
  count="$(cat "$d/stop-blocks" 2>/dev/null)"; [[ "$count" =~ ^[0-9]+$ ]] || count=0
fi

prs=""; lines=""
while read -r key; do
  [[ -n "$key" ]] || continue
  prs+="$key, "
  lines+=" - $key: send its author \"PR #${key##*#} merged. Next: <issue | handover | stand by | done>\" (a per-issue agent meeting the strict conditions: \"Next: #<m> (same session)\"; or \"PR $key merged. Next: ...\")."
done <<<"$pending"
prs="${prs%, }"

if (( count >= max )); then
  rm -f "$d/stop-blocks"
  msg="Coordinator: ${prs} merged without a Next message to the author; the agent is waiting and will stay idle. Stop allowed after ${max} blocks. Send it next turn, or clear it with scripts/next-clear.sh and a reason."
  printf '{"systemMessage":%s}\n' "$(json_string "$msg")"
  exit 0
fi
echo $((count + 1)) >"$d/stop-blocks"
reason="Coordinator: merged PR(s) ${prs} still need the author told what is next (review-merge.md, step 9). The agent waits after \"PR ready\" and runs only when a message arrives.${lines} Read the author's context first (mcp__ccd_session_mgmt__get_usage): at or past the soft limit, Next: handover; a per-issue agent, Next: done (then archive it); otherwise the next issue, or stand by. Send it with SendMessage to the author's session by name. If the author can no longer receive a message (session archived or deleted), clear it with a reason the ledger keeps: bash \"${plugin}/scripts/next-clear.sh\" ${sid} <owner/repo#N> \"<reason>\"."
printf '{"decision":"block","reason":%s}\n' "$(json_string "$reason")"
