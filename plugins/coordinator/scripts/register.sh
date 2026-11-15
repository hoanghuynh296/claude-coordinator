#!/usr/bin/env bash
# Register (or unregister) a Claude session as the project coordinator.
# Usage: register.sh <session_id> <ledger_dir> [project_dir]
#        register.sh --unregister <session_id>
# Writes ${COORDINATOR_HOME:-$HOME/.claude/coordinator}/sessions/<session_id>.
set -euo pipefail

home="${COORDINATOR_HOME:-$HOME/.claude/coordinator}"

if [[ "${1:-}" == "--unregister" ]]; then
  sid="${2:?session id required}"
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid session id: $sid" >&2; exit 1; }
  if [[ -f "$home/sessions/$sid" ]]; then
    mv "$home/sessions/$sid" "$home/sessions/$sid.unregistered"
    echo "unregistered $sid (file kept as $sid.unregistered)"
  else
    echo "session $sid was not registered"
  fi
  exit 0
fi

sid="${1:?usage: register.sh <session_id> <ledger_dir> [project_dir]}"
ledger="${2:?ledger dir required}"
project="${3:-}"

if [[ ! "$sid" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "invalid session id '$sid' (was \${CLAUDE_SESSION_ID} substituted?)" >&2
  exit 1
fi
[[ -d "$ledger" ]] || { echo "ledger dir not found: $ledger" >&2; exit 1; }
[[ -f "$ledger/COORDINATION.md" ]] || echo "warning: $ledger/COORDINATION.md does not exist yet" >&2
ledger="$(cd "$ledger" && pwd -P)"
if [[ -n "$project" ]]; then
  [[ -d "$project" ]] || { echo "project dir not found: $project" >&2; exit 1; }
  project="$(cd "$project" && pwd -P)"
fi

mkdir -p "$home/sessions"
{
  echo "ledger=$ledger"
  echo "project=$project"
  echo "registered=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$home/sessions/$sid"
echo "registered coordinator session $sid"
echo "  ledger:  $ledger"
echo "  project: ${project:-<any>}"
