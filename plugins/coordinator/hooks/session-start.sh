#!/usr/bin/env bash
# SessionStart: remind a registered coordinator where its ledger is. Silent otherwise.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
reg="$(registration_file "$sid")" || exit 0

ledger="$(reg_value "$reg" ledger)"
project="$(reg_value "$reg" project)"

echo "You are the COORDINATOR for this project (registered by the coordinator plugin)."
echo "Ledger: ${ledger}/COORDINATION.md  (handover notes: ${ledger}/handover/)"
[[ -n "$project" ]] && echo "Project repo: ${project}"
[[ -d "$ledger" ]] || echo "WARNING: ledger dir not found; re-run /coordinator:coordinator-register."
echo "Read COORDINATION.md and the newest handover note before acting. Use the coordinator skill."
echo "You never edit product code (a hook denies it): delegate via tickets, lanes or subagents."
echo "Measure contexts on each owner message; rotate any session (yours included) at ~250k tokens."
exit 0
