#!/usr/bin/env bash
# SessionStart: remind a registered coordinator where its ledger is. Silent otherwise.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
reg="$(registration_file "$sid")" || exit 0

ledger="$(reg_value "$reg" ledger)"
guard="$(reg_value "$reg" guard)"

echo "You are the COORDINATOR for this project (registered by the coordinator plugin)."
echo "Ledger: ${ledger}"
if [[ -f "$ledger/coordination/README.md" ]]; then
  echo "Read ${ledger}/coordination/README.md and follow its read order (COORDINATION.md, PROFILE.md, ROADMAP.md, your handover note) before acting."
else
  echo "Read ${ledger}/COORDINATION.md before acting. The ledger is not in the standard layout: run /coordinator:adopt."
fi
while IFS= read -r u; do [[ -n "$u" ]] && echo "Unit: ${u}"; done < <(reg_values "$reg" unit; reg_values "$reg" project)
[[ -d "$ledger" ]] || echo "WARNING: ledger dir not found; re-run /coordinator:coordinator-register."
if [[ "$guard" == "off" ]]; then
  echo "Edit guard: off (the project's profile lets the coordinator edit code)."
else
  echo "Edit guard: on. Inside units you may edit only the planning files the profile allows; delegate the rest through issues."
fi
echo "The project's rules are in coordination/PROFILE.md, not in your memory. Measure contexts on each owner message."
exit 0
