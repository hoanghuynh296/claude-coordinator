#!/usr/bin/env bash
# Pipe sample hook inputs into the coordinator hooks and check the decisions.
# Uses a temporary COORDINATOR_HOME, so the real ~/.claude/coordinator is untouched.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
hooks="$root/plugins/coordinator/hooks"
tmp="$root/tests/.work"; rm -rf "$tmp"; mkdir -p "$tmp"  # not under a temp dir: temp dirs are allowed paths
export COORDINATOR_HOME="$tmp/home"
mkdir -p "$tmp/proj/docs/adr" "$tmp/proj/src" "$tmp/ledger"
touch "$tmp/ledger/COORDINATION.md"
"$root/plugins/coordinator/scripts/register.sh" coord-1 "$tmp/ledger" "$tmp/proj" >/dev/null
L="$(cd "$tmp/ledger" && pwd -P)"; P="$(cd "$tmp/proj" && pwd -P)"

pass=0; failn=0
check() { # name expected(allow|deny) json
  local out decision
  out="$(printf '%s' "$3" | bash "$hooks/coordinator-guard.sh")"
  if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then decision=deny; else decision=allow; fi
  if [[ "$decision" == "$2" ]]; then pass=$((pass+1)); printf 'PASS %-5s %s\n' "$decision" "$1"
  else failn=$((failn+1)); printf 'FAIL got %s want %s: %s\n%s\n' "$decision" "$2" "$1" "$out"; fi
}
ev() { # session tool path-field path
  printf '{"session_id":"%s","cwd":"%s","scratchpad_dir":"/private/tmp/claude-x/scratch","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$1" "$P" "$2" "$3" "$4"
}

for mode in jq python3; do
  echo "--- JSON via $mode"
  if [[ $mode == python3 ]]; then export COORDINATOR_NO_JQ=1; fi
  check "ledger file"            allow "$(ev coord-1 Write file_path "$L/COORDINATION.md")"
  check "ledger handover"        allow "$(ev coord-1 Write file_path "$L/handover/2026-11-16-coordinator.md")"
  check "docs/PLAN.md"           allow "$(ev coord-1 Edit file_path "$P/docs/PLAN.md")"
  check "docs/adr/0001"          allow "$(ev coord-1 Write file_path "$P/docs/adr/0001-db.md")"
  check "contracts README"       allow "$(ev coord-1 Edit file_path "$P/docs/contracts/README.md")"
  check "AGENTS.md"              allow "$(ev coord-1 Edit file_path "$P/AGENTS.md")"
  check "relative docs/PLAN.md"  allow "$(ev coord-1 Edit file_path "docs/PLAN.md")"
  check "memory ~/.claude"       allow "$(ev coord-1 Write file_path "$HOME/.claude/projects/x/memory/MEMORY.md")"
  check "scratchpad"             allow "$(ev coord-1 Write file_path "/private/tmp/claude-x/scratch/PLAN.md")"
  check "code src/app.ts"        deny  "$(ev coord-1 Write file_path "$P/src/app.ts")"
  check "CI workflow"            deny  "$(ev coord-1 Edit file_path "$P/.github/workflows/ci.yml")"
  check "Makefile multiedit"     deny  "$(ev coord-1 MultiEdit file_path "$P/Makefile")"
  check "notebook"               deny  "$(ev coord-1 NotebookEdit notebook_path "$P/src/a.ipynb")"
  check "traversal via docs/.."  deny  "$(ev coord-1 Write file_path "$P/docs/adr/../../src/x.ts")"
  check "contracts spec file"    deny  "$(ev coord-1 Write file_path "$P/docs/contracts/openapi.yaml")"
  check "other repo AGENTS.md"   deny  "$(ev coord-1 Edit file_path "/Users/someone/other/src/AGENTS.md.ts")"
  check "unregistered session"   allow "$(ev lane-7 Write file_path "$P/src/app.ts")"
  check "bad session id"         allow "$(ev '../x' Write file_path "$P/src/app.ts")"
done
unset COORDINATOR_NO_JQ

echo "--- multi-repo workspace: units live inside the ledger dir, custom allow list"
W="$tmp/ws"; mkdir -p "$W/coordination/handover" "$W/products/app/src" "$W/products/app/docs/design" "$W/products/lib/docs"
touch "$W/COORDINATION.md"
"$root/plugins/coordinator/scripts/register.sh" coord-2 "$W" "$W/products/app" "$W/products/lib" \
  --allow 'docs/PLAN.md' --allow 'docs/design/*' >/dev/null
WS="$(cd "$W" && pwd -P)"
P="$WS/products/app"
check "ws ledger file"            allow "$(ev coord-2 Write file_path "$WS/COORDINATION.md")"
check "ws coordination/PROFILE"   allow "$(ev coord-2 Edit file_path "$WS/coordination/PROFILE.md")"
check "ws unit code under ledger" deny  "$(ev coord-2 Write file_path "$WS/products/app/src/main.py")"
check "ws second unit code"       deny  "$(ev coord-2 Write file_path "$WS/products/lib/setup.py")"
check "ws allowed docs/PLAN.md"   allow "$(ev coord-2 Edit file_path "$WS/products/lib/docs/PLAN.md")"
check "ws allowed docs/design/*"  allow "$(ev coord-2 Write file_path "$WS/products/app/docs/design/ui.md")"
check "ws AGENTS.md not in list"  deny  "$(ev coord-2 Edit file_path "$WS/products/app/AGENTS.md")"
check "ws traversal into unit"    deny  "$(ev coord-2 Write file_path "$WS/coordination/../products/app/src/x.py")"

echo "--- registered without the guard"
"$root/plugins/coordinator/scripts/register.sh" coord-3 "$W" "$W/products/app" --no-guard >/dev/null
check "no-guard unit code"        allow "$(ev coord-3 Write file_path "$WS/products/app/src/main.py")"

echo "--- register.sh rejects bad input"
if "$root/plugins/coordinator/scripts/register.sh" coord-4 "$W" --allow '/abs/path' >/dev/null 2>&1; then
  failn=$((failn+1)); echo "FAIL absolute --allow accepted"
else pass=$((pass+1)); echo "PASS absolute --allow rejected"; fi
if "$root/plugins/coordinator/scripts/register.sh" coord-4 "$W" "$W/nope" >/dev/null 2>&1; then
  failn=$((failn+1)); echo "FAIL missing unit dir accepted"
else pass=$((pass+1)); echo "PASS missing unit dir rejected"; fi
P="$(cd "$tmp/proj" && pwd -P)"

echo "--- sample deny output:"
ev coord-1 Write file_path "$P/src/app.ts" | bash "$hooks/coordinator-guard.sh"
echo "--- SessionStart (registered):"
printf '{"session_id":"coord-1","hook_event_name":"SessionStart","source":"startup"}' | bash "$hooks/session-start.sh"
echo "--- SessionStart (unregistered, expect nothing):"
printf '{"session_id":"lane-7","hook_event_name":"SessionStart","source":"startup"}' | bash "$hooks/session-start.sh"
echo "---"
rm -rf "$tmp"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
