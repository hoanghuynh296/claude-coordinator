#!/usr/bin/env bash
# Register (or unregister) a Claude session as the project coordinator.
# Usage: register.sh <session_id> <ledger_dir> [unit_dir...] [--allow GLOB]... [--allow-none] [--no-guard]
#        register.sh --unregister <session_id>
#
#   unit_dir     a unit checkout the coordinator must not edit freely (repeatable). In a
#                multi-repo workspace these are folders inside the ledger dir.
#   --allow GLOB a path, relative to a unit root, that the coordinator may edit inside units
#                (repeatable). Default when none is given: docs/PLAN.md, docs/adr/*,
#                docs/contracts/README.md, AGENTS.md.
#   --allow-none the coordinator may edit nothing inside units (no default list).
#   --no-guard   register without the edit guard (the profile lets the coordinator edit code).
#
# Writes ${COORDINATOR_HOME:-$HOME/.claude/coordinator}/sessions/<session_id>.
set -euo pipefail

home="${COORDINATOR_HOME:-$HOME/.claude/coordinator}"

if [[ "${1:-}" == "--unregister" ]]; then
  sid="${2:?session id required}"
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid session id: $sid" >&2; exit 1; }
  if [[ -f "$home/sessions/$sid" ]]; then
    mv "$home/sessions/$sid" "$home/sessions/$sid.unregistered"
    rm -rf "${home:?}/state/$sid"
    echo "unregistered $sid (file kept as $sid.unregistered; hook state removed)"
  else
    echo "session $sid was not registered"
  fi
  exit 0
fi

sid="${1:?usage: register.sh <session_id> <ledger_dir> [unit_dir...] [--allow GLOB]... [--allow-none] [--no-guard]}"
ledger="${2:?ledger dir required}"
shift 2

if [[ ! "$sid" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "invalid session id '$sid' (was \${CLAUDE_SESSION_ID} substituted?)" >&2
  exit 1
fi
[[ -d "$ledger" ]] || { echo "ledger dir not found: $ledger" >&2; exit 1; }
[[ -f "$ledger/COORDINATION.md" ]] || echo "warning: $ledger/COORDINATION.md does not exist yet" >&2
ledger="$(cd "$ledger" && pwd -P)"

units=(); allows=(); guard=on; allow_none=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow) allows+=("${2:?--allow needs a glob}"); shift 2 ;;
    --allow-none) allow_none=1; shift ;;
    --no-guard) guard=off; shift ;;
    --*) echo "unknown option: $1" >&2; exit 2 ;;
    "") shift ;;
    *)
      [[ -d "$1" ]] || { echo "unit dir not found: $1" >&2; exit 1; }
      units+=("$(cd "$1" && pwd -P)"); shift ;;
  esac
done
for a in ${allows[@]+"${allows[@]}"}; do
  case "$a" in /*|*..*|*$'\n'*) echo "--allow must be a relative glob without '..': $a" >&2; exit 2 ;; esac
done

mkdir -p "$home/sessions"
{
  echo "ledger=$ledger"
  for u in ${units[@]+"${units[@]}"}; do echo "unit=$u"; done
  for a in ${allows[@]+"${allows[@]}"}; do echo "allow=$a"; done
  [[ $allow_none -eq 1 ]] && echo "allow_none=1"
  echo "guard=$guard"
  echo "registered=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$home/sessions/$sid"
echo "registered coordinator session $sid"
echo "  ledger: $ledger"
if [[ ${#units[@]} -gt 0 ]]; then
  for u in "${units[@]}"; do echo "  unit:   $u"; done
else
  echo "  units:  <none recorded: everything outside the ledger is guarded>"
fi
echo "  guard:  $guard"
