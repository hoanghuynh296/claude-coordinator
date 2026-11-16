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

echo "--- registered with --allow-none"
"$root/plugins/coordinator/scripts/register.sh" coord-5 "$W" "$W/products/app" --allow-none >/dev/null
check "allow-none AGENTS.md"      deny  "$(ev coord-5 Edit file_path "$WS/products/app/AGENTS.md")"
check "allow-none docs/PLAN.md"   deny  "$(ev coord-5 Edit file_path "$WS/products/app/docs/PLAN.md")"
check "allow-none ledger file"    allow "$(ev coord-5 Write file_path "$WS/coordination/ROADMAP.md")"

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
ss() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" "$2" | bash "$hooks/session-start.sh"; }
expect_out() { # name needle-or-EMPTY output
  if [[ "$2" == EMPTY && -z "$3" ]] || [[ "$2" != EMPTY && "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "PASS $1"
  else failn=$((failn+1)); printf 'FAIL %s (want: %s)\n%s\n' "$1" "$2" "$3"; fi
}
echo "--- SessionStart hints for unregistered sessions"
mkdir -p "$WS/coordination" "$tmp/wrap/one/coordination" "$tmp/wrap/two/coordination" "$tmp/plain/sub"
touch "$tmp/wrap/one/COORDINATION.md"
expect_out "ledger folder: hint with the session id" "session id new-1" "$(ss new-1 "$WS")"
expect_out "ledger folder: names the ledger"         "$WS"              "$(ss new-1 "$WS")"
expect_out "wrapper folder with one ledger"          "$tmp/wrap/one"    "$(ss new-2 "$tmp/wrap")"
touch "$tmp/wrap/two/COORDINATION.md"
expect_out "wrapper folder with two ledgers"         "several coordination ledgers" "$(ss new-2 "$tmp/wrap")"
expect_out "unit checkout inside a workspace"        "unit of a coordinated project" "$(ss agent-1 "$WS/products/app")"
expect_out "ordinary folder: silent"                 EMPTY              "$(ss new-3 "$tmp/plain")"
expect_out "registered session: coordinator text"    "You are the COORDINATOR" "$(ss coord-2 "$tmp/plain")"
echo "--- PostToolUse merge reminder"
mr() { printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" | bash "$hooks/merge-reminder.sh"; }
expect_out "merge by coordinator: archive reminder"  "archive_session" "$(mr coord-1 'gh pr merge 12 --repo o/r --merge --delete-branch')"
expect_out "merge after cd &&: reminder"             "archive_session" "$(mr coord-1 'cd x && gh pr merge 12')"
expect_out "gh pr view: silent"                      EMPTY "$(mr coord-1 'gh pr view 12')"
expect_out "merge by unregistered session: silent"   EMPTY "$(mr lane-7 'gh pr merge 12')"
expect_out "merge reminder via python3" "archive_session" "$(COORDINATOR_NO_JQ=1 mr coord-1 'gh pr merge 12')"
echo "--- one issue, one lifecycle: pending Next after a merge, cleared by the merge notice, Stop guard"
rm -rf "$COORDINATOR_HOME/state"
pend() { cat "$COORDINATOR_HOME/state/$1/pending-next" 2>/dev/null | awk '{printf "%s ", $1}'; }
expect_eq() { # name want got
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); echo "PASS $1"
  else failn=$((failn+1)); printf 'FAIL %s (want "%s", got "%s")\n' "$1" "$2" "$3"; fi
}
mrr() { # session command response-json
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":%s}' "$1" "$2" "${3:-{\"stdout\":\"\",\"stderr\":\"\",\"interrupted\":false\}}" | bash "$hooks/merge-reminder.sh"; }
sm() { # session tool field text
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"PostToolUse","tool_name":sys.argv[2],"tool_input":{"to":"Agent: api",sys.argv[3]:sys.argv[4]},"tool_response":{}}))' "$1" "$2" "$3" "$4" \
    | bash "$hooks/next-sent.sh"; }
stop() { # session stop_hook_active
  printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2" | bash "$hooks/next-guard.sh"; }

expect_out "merge records pending, says so"            "Pending until sent" "$(mrr coord-1 'gh pr merge 12 --repo o/r --merge --delete-branch')"
expect_eq  "pending holds #12"                         "12 " "$(pend coord-1)"
expect_eq  "pending keeps the repo"                    "o/r" "$(awk '{print $2}' "$COORDINATOR_HOME/state/coord-1/pending-next")"
mrr coord-1 'cd x && gh pr merge -R o/r2 --squash \"#13\" && gh pr merge https://github.com/o/r3/pull/14 --merge' >/dev/null
expect_eq  "-R, #N and URL forms, two merges"          "12 13 14 " "$(pend coord-1)"
expect_eq  "URL gives the repo"                        "o/r3" "$(awk '$1==14 {print $2}' "$COORDINATOR_HOME/state/coord-1/pending-next")"
mrr coord-1 'gh pr merge 15 --auto --squash' >/dev/null
expect_eq  "--auto is not a merge yet"                 "12 13 14 " "$(pend coord-1)"
mrr coord-1 'gh pr merge 16' '{"stdout":"","stderr":"GraphQL: Pull request is not mergeable","interrupted":false}' >/dev/null
expect_eq  "failed merge is not recorded"              "12 13 14 " "$(pend coord-1)"
mrr coord-1 'gh pr merge 17' '{"stdout":"","stderr":"","interrupted":true}' >/dev/null
expect_eq  "interrupted merge is not recorded"         "12 13 14 " "$(pend coord-1)"
expect_out "branch-name merge: asks for the number"    "could not be read" "$(mrr coord-1 'gh pr merge feature-x')"
mrr lane-7 'gh pr merge 18' >/dev/null
expect_eq  "unregistered merge: no state"              "" "$(ls "$COORDINATOR_HOME/state" | grep lane-7 || true)"

out="$(stop coord-1 false)"
expect_out "Stop blocks while pending"                 '"decision":"block"' "$out"
expect_out "Stop reason names each PR"                 'PR #13 merged. Next:' "$out"
expect_out "Stop reason gives the escape hatch"        'next-clear.sh' "$out"
expect_out "Stop reason via python3"                   '"decision":"block"' "$(COORDINATOR_NO_JQ=1 stop coord-1 false)"

expect_eq  "message without Next: line keeps pending"  "" "$(sm coord-1 SendMessage message 'PR #12 merged.')"
expect_eq  "wrong PR number keeps pending"             "" "$(sm coord-1 SendMessage message $'PR #99 merged.\nNext: #50')"
expect_eq  "empty Next: keeps pending"                 "" "$(sm coord-1 SendMessage message 'PR #12 merged. Next:   ')"
expect_eq  "unregistered sender: silent"               "" "$(sm lane-7 SendMessage message 'PR #12 merged. Next: #50')"
expect_eq  "still 12 13 14"                            "12 13 14 " "$(pend coord-1)"
expect_out "notice clears #12, lists what is left"     "Still pending: #13 #14" "$(sm coord-1 SendMessage message 'PR #12 merged. Next: #50 https://github.com/o/r/issues/50')"
expect_out "send_message tool clears #13 (Next on its own line)" "Next sent for #13" \
  "$(sm coord-1 mcp__ccd_session_mgmt__send_message message $'PR #13 merged.\nNext: handover')"
expect_eq  "only #14 left"                             "14 " "$(pend coord-1)"

echo "--- Stop guard cannot loop: at most 3 blocks per turn, then allow with a warning"
rm -f "$COORDINATOR_HOME/state/coord-1/stop-blocks"
expect_out "turn end: block 1"                         '"decision":"block"' "$(stop coord-1 false)"
expect_out "continued: block 2"                        '"decision":"block"' "$(stop coord-1 true)"
expect_out "continued: block 3"                        '"decision":"block"' "$(stop coord-1 true)"
out="$(stop coord-1 true)"
expect_out "continued: 4th stop allowed with warning"  'systemMessage' "$out"
[[ "$out" != *'"decision":"block"'* ]] && { pass=$((pass+1)); echo "PASS 4th stop is not blocked"; } || { failn=$((failn+1)); echo "FAIL 4th stop blocked"; }
expect_out "next turn blocks again"                    '"decision":"block"' "$(stop coord-1 false)"
expect_eq  "unregistered Stop: silent"                 "" "$(stop lane-7 false)"
expect_eq  "registered, nothing pending: silent"       "" "$(stop coord-2 false)"

echo "--- escape hatch: next-clear.sh needs a reason and logs it in the ledger"
nc="$root/plugins/coordinator/scripts/next-clear.sh"
if bash "$nc" coord-1 14 >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL clear without reason accepted"; else pass=$((pass+1)); echo "PASS clear without reason rejected"; fi
if bash "$nc" lane-7 14 "x" >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL unregistered clear accepted"; else pass=$((pass+1)); echo "PASS unregistered clear rejected"; fi
mkdir -p "$L/coordination"
bash "$nc" coord-1 '#14' "author session archived before the merge" >/dev/null
expect_eq  "cleared: nothing pending"                  "" "$(pend coord-1)"
expect_out "reason is in the ledger"                   "PR #14: author session archived" "$(cat "$L/coordination/next-cleared.md")"
expect_eq  "Stop allowed once cleared"                 "" "$(stop coord-1 false)"
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$hooks/hooks.json" && { pass=$((pass+1)); echo "PASS hooks.json parses"; } \
  || { failn=$((failn+1)); echo "FAIL hooks.json does not parse"; }
echo "---"
rm -rf "$tmp"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
