#!/usr/bin/env bash
# Clear a merged PR that waits for its "PR #N merged. Next: ..." message, when that message
# cannot be sent (the author's session was archived or deleted, the PR had no agent author).
# The reason is kept in the ledger: one line appended to coordination/next-cleared.md of the
# ledger this coordinator is registered with; commit it with the next ledger commit.
# Usage: next-clear.sh <session_id> <pr_number> <reason...>
#        next-clear.sh <session_id> --list
set -euo pipefail

# shellcheck source=../hooks/lib.sh
. "$(dirname "$0")/../hooks/lib.sh"

usage() { sed -n '6,7p' "$0" | sed 's/^# //' >&2; exit 2; }
sid="${1:-}"; [[ -n "$sid" ]] || usage
reg="$(registration_file "$sid")" || { echo "session $sid is not a registered coordinator" >&2; exit 1; }
if [[ "${2:-}" == "--list" ]]; then pending_list "$sid"; exit 0; fi
pr="${2:-}"; pr="${pr#\#}"
[[ "$pr" =~ ^[0-9]+$ ]] || usage
shift 2
reason="$*"
[[ -n "${reason// /}" ]] || { echo "a reason is required (it is kept in the ledger)" >&2; exit 2; }
reason="${reason//$'\n'/ }"

pending_remove "$sid" "$pr" || { echo "PR #$pr is not pending a Next message"; exit 1; }
ledger="$(reg_value "$reg" ledger)"
log="$ledger/coordination/next-cleared.md"
if [[ -d "$ledger/coordination" ]]; then
  [[ -f "$log" ]] || printf '# Merged PRs cleared without a Next message\n\nAppended by next-clear.sh; one line each.\n\n' >"$log"
  printf -- '- %s PR #%s: %s\n' "$(date -u +%Y-%m-%d)" "$pr" "$reason" >>"$log"
  echo "cleared PR #$pr; reason appended to $log (commit it with the ledger)"
else
  echo "cleared PR #$pr; WARNING: no coordination/ dir in $ledger, record the reason in COORDINATION.md" >&2
fi
