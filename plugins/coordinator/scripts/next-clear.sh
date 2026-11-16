#!/usr/bin/env bash
# Manage the merged PRs that wait for their "PR #N merged. Next: ..." message (the Stop hook
# next-guard.sh blocks a coordinator's turn while any is pending).
# Usage: next-clear.sh <session_id> <owner/repo#N | N> <reason...>   clear one, reason kept in the ledger
#        next-clear.sh <session_id> --list                            print what is pending
#        next-clear.sh <session_id> --handover                        print it and drop this session's state
#        next-clear.sh <session_id> --add <owner/repo#N>...           record PRs carried over from a handover
#
# Clear: when the message cannot be sent (the author's session was archived or deleted, the PR
# had no agent author). One line is appended to coordination/next-cleared.md of the ledger
# this coordinator is registered with; commit it with the next ledger commit.
# Handover: an old coordinator writes the --handover output into its handover note ("Pending
# Next"); its replacement, once registered, runs --add with those keys and sends the messages.
set -euo pipefail

# shellcheck source=../hooks/lib.sh
. "$(dirname "$0")/../hooks/lib.sh"

usage() { sed -n '4,7p' "$0" | sed 's/^# //' >&2; exit 2; }
sid="${1:-}"; [[ -n "$sid" ]] || usage
reg="$(registration_file "$sid")" || { echo "session $sid is not a registered coordinator" >&2; exit 1; }
case "${2:-}" in
  --list) pending_keys "$sid"; exit 0 ;;
  --handover)
    pending_keys "$sid"
    rm -rf "${COORD_HOME:?}/state/$sid"
    exit 0 ;;
  --add)
    shift 2; [[ $# -gt 0 ]] || usage
    for k in "$@"; do
      valid_key "$k" || { echo "not owner/repo#N: $k" >&2; exit 2; }
      pending_add "$sid" "$k"; echo "pending: $k"
    done
    exit 0 ;;
  "") usage ;;
esac
ref="$2"; shift 2
reason="$*"
[[ -n "${reason// /}" ]] || { echo "a reason is required (it is kept in the ledger)" >&2; exit 2; }
reason="${reason//$'\n'/ }"

rc=0; key="$(pending_resolve "$sid" "$ref")" || rc=$?
[[ $rc -eq 2 ]] && { echo "#${ref#\#} is pending in more than one repo; give owner/repo#N" >&2; exit 1; }
[[ $rc -eq 0 ]] || { echo "$ref is not pending a Next message"; exit 1; }
pending_remove "$sid" "$key"
ledger="$(reg_value "$reg" ledger)"
log="$ledger/coordination/next-cleared.md"
if [[ -d "$ledger/coordination" ]]; then
  [[ -f "$log" ]] || printf '# Merged PRs cleared without a Next message\n\nAppended by next-clear.sh; one line each.\n\n' >"$log"
  printf -- '- %s %s: %s\n' "$(date -u +%Y-%m-%d)" "$key" "$reason" >>"$log"
  echo "cleared $key; reason appended to $log (commit it with the ledger)"
else
  echo "cleared $key; WARNING: no coordination/ dir in $ledger, record the reason in COORDINATION.md" >&2
fi
