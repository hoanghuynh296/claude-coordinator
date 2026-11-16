#!/usr/bin/env bash
# SessionStart hook. Prints context for Claude; silent when there is nothing to say.
#
#   1. Session registered as coordinator: where the ledger is and what the guard does.
#   2. Not registered, but the working folder is a coordination ledger (or holds exactly one):
#      a hint, so that the owner can simply start talking and the session takes up the
#      coordinator role through the skill. Nothing is registered by the hook itself.
#   3. Not registered, and the working folder is a unit checkout inside a ledger workspace
#      (<ledger>/products/<unit>): a short reminder of how a unit agent works.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
cwd="$(json_get "$input" cwd)"
[[ -n "$cwd" ]] || cwd="$PWD"

is_ledger() { [[ -f "$1/COORDINATION.md" && -d "$1/coordination" ]]; }

if reg="$(registration_file "$sid")"; then
  ledger="$(reg_value "$reg" ledger)"
  guard="$(reg_value "$reg" guard)"
  echo "You are the COORDINATOR for this project (registered by the coordinator plugin)."
  echo "Ledger: ${ledger}"
  if [[ -f "$ledger/coordination/README.md" ]]; then
    echo "Read ${ledger}/coordination/README.md and follow its read order (COORDINATION.md, PROFILE.md, ROADMAP.md, your handover note) before acting."
  else
    echo "Read ${ledger}/COORDINATION.md before acting. The ledger is not in the standard layout: follow the coordinator skill's adopt procedure."
  fi
  while IFS= read -r u; do [[ -n "$u" ]] && echo "Unit: ${u}"; done < <(reg_values "$reg" unit; reg_values "$reg" project)
  [[ -d "$ledger" ]] || echo "WARNING: ledger dir not found; register again (coordinator skill, coordinator-register procedure)."
  if [[ "$guard" == "off" ]]; then
    echo "Edit guard: off (the project's profile lets the coordinator edit code)."
  else
    echo "Edit guard: on. Inside units you may edit only the planning files the profile allows; delegate the rest through issues."
  fi
  echo "The project's rules are in coordination/PROFILE.md, not in your memory. The owner speaks plain language: load the coordinator skill and pick the procedure yourself. Measure contexts on each owner message."
  exit 0
fi

[[ -d "$cwd" ]] || exit 0

# 2. The working folder is a ledger, or holds exactly one.
ledgers=()
if is_ledger "$cwd"; then
  ledgers+=("$cwd")
else
  for d in "$cwd"/*/; do
    d="${d%/}"
    is_ledger "$d" && ledgers+=("$d")
  done
fi
if [[ ${#ledgers[@]} -ge 1 ]]; then
  if [[ ${#ledgers[@]} -eq 1 ]]; then
    echo "This folder holds a coordination ledger (claude-coordinator kit): ${ledgers[0]}"
  else
    echo "This folder holds several coordination ledgers (claude-coordinator kit):"
    for l in "${ledgers[@]}"; do echo "  - $l"; done
    echo "Ask the owner which project they mean if it is not clear from what they say."
  fi
  echo "This session is not registered as its coordinator yet. If the owner talks about the project's work (status, new work, agents, a PR, a release), load the coordinator skill, register this session (session id ${sid}) with its coordinator-register procedure, and follow the read order in coordination/README.md. The owner does not need to type any command."
  exit 0
fi

# 3. A unit checkout inside a ledger workspace: <ledger>/products/<unit>.
parent="$(dirname "$cwd")"
if [[ "$(basename "$parent")" == "products" ]] && is_ledger "$(dirname "$parent")"; then
  echo "This repo is a unit of a coordinated project (ledger: $(dirname "$parent")). If you are its agent: follow this repo's AGENTS.md; work arrives as issues with acceptance criteria; one issue, one branch from the integration branch, one PR; never merge your own PR; report to the coordinator only when the PR is ready or you are blocked. One issue at a time: after \"PR ready\" wait for the coordinator's \"PR #<n> merged. Next: ...\" before starting anything new."
fi
exit 0
