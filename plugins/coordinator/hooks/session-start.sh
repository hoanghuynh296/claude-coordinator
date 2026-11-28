#!/usr/bin/env bash
# SessionStart hook. Prints context for Claude; silent when there is nothing to say.
#
#   1. Session registered as coordinator: where the ledger is and what the guard does.
#   2. Not registered, but the working folder is a coordination ledger (or holds exactly one):
#      a hint, so that the owner can simply start talking and the session takes up the
#      coordinator role through the skill. Nothing is registered by the hook itself.
#   3. Not registered, and the working folder is a unit checkout inside a ledger workspace
#      (<ledger>/products/<unit>): a short reminder of how a unit agent works.
# Each of the three ends with one kit line (#54): the kit version this session runs, or, when a
# newer one is installed for this runtime, that the session rotates at the next safe point. The
# version is recorded per session (kit_running in lib.sh); kit-notice.sh compares it on later
# owner turns, since this hook runs only at a start, resume or compaction.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(hook_sid "$input")" || exit 0
ag=0; is_antigravity "$input" && ag=1
cwd="$(json_get "$input" cwd)"
if [[ -z "$cwd" ]] && (( ag )); then
  cwd="$(json_get "$input" workspacePaths.0)"
fi
[[ -n "$cwd" ]] || cwd="$PWD"
silent() { (( ag )) && printf '{}\n'; exit 0; }
finish() {
  local msg="$1" kl
  kl="$(kit_line "$sid" "$( (( ag )) && echo ag)" 2>/dev/null || true)"
  [[ -n "$kl" ]] && msg+="
$kl"
  if (( ag )); then
    printf '{"injectSteps":[{"systemMessage":{"systemMessage":%s}}]}\n' "$(json_string "$msg")"
  else
    printf '%s\n' "$msg"
  fi
  exit 0
}

is_ledger() { [[ -f "$1/COORDINATION.md" && -d "$1/coordination" ]]; }

if reg="$(registration_file "$sid")"; then
  ledger="$(reg_value "$reg" ledger)"
  guard="$(reg_value "$reg" guard)"
  out="You are the COORDINATOR for this project (registered by the coordinator plugin).
Ledger: ${ledger}"
  if [[ -f "$ledger/coordination/README.md" ]]; then
    out+="
Read ${ledger}/coordination/README.md and follow its read order (COORDINATION.md, PROFILE.md, ROADMAP.md, your handover note) before acting."
  else
    out+="
Read ${ledger}/COORDINATION.md before acting. The ledger is not in the standard layout: follow the coordinator skill's adopt procedure."
  fi
  while IFS= read -r u; do [[ -n "$u" ]] && out+="
Unit: ${u}"; done < <(reg_values "$reg" unit; reg_values "$reg" project)
  [[ -d "$ledger" ]] || out+="
WARNING: ledger dir not found; register again (coordinator skill, coordinator-register procedure)."
  if [[ "$guard" == "off" ]]; then
    out+="
Edit guard: off (the project's profile lets the coordinator edit code)."
  else
    out+="
Edit guard: on. Inside units you may edit only the planning files the profile allows; delegate the rest through issues."
  fi
  out+="
The project's rules are in coordination/PROFILE.md, not in your memory. The owner speaks plain language: load the coordinator skill and pick the procedure yourself."
  finish "$out"
fi

[[ -d "$cwd" ]] || silent

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
    out="This folder holds a coordination ledger (claude-coordinator kit): ${ledgers[0]}"
  else
    out="This folder holds several coordination ledgers (claude-coordinator kit):"
    for l in "${ledgers[@]}"; do out+="
  - $l"; done
    out+="
Ask the owner which project they mean if it is not clear from what they say."
  fi
  out+="
This session is not registered as its coordinator yet. If the owner talks about the project's work (status, new work, agents, a PR, a release), load the coordinator skill, register this session (session id ${sid}) with its coordinator-register procedure, and follow the read order in coordination/README.md. The owner does not need to type any command."
  finish "$out"
fi

# 3. A unit checkout inside a ledger workspace: <ledger>/products/<unit>.
parent="$(dirname "$cwd")"
if [[ "$(basename "$parent")" == "products" ]] && is_ledger "$(dirname "$parent")"; then
  finish "This repo is a unit of a coordinated project (ledger: $(dirname "$parent")). If you are its agent: follow this repo's AGENTS.md; work arrives as issues with acceptance criteria; one issue, one branch from the integration branch, one PR; never merge your own PR; report to the coordinator only when the PR is ready or you are blocked. Report \"PR ready\" as soon as the PR is pushed and the local gate (lint and tests) is green; the FIRST line of that message starts with \"PR ready:\" (the coordinator's hook reacts only to that; use the phrase in no other message), then the head SHA and the CI state (pending, green or red); never wait for CI (a green run wakes nobody; the coordinator watches it), and end with Context: <k tokens>. One issue at a time: after \"PR ready\" wait for the coordinator's \"PR #<n> merged. Next: ...\" before starting anything new."
fi
silent
