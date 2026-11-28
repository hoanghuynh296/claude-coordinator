#!/usr/bin/env bash
# rotation-guard.sh (#47) against fake coordinator transcripts and a local ledger repo:
# ok / soft / hard, PROFILE Budgets, owner and non-owner turns, the handover and Remote Control
# owner-queue escapes, running subagents, merges in flight, the block cap, fail-open errors,
# Antigravity payloads and ag-chain.sh. Temporary COORDINATOR_HOME; the real one is untouched.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
hooks="$root/plugins/coordinator/hooks"
w="$root/tests/.work/rotation"; rm -rf "${w:?}"; mkdir -p "$w/config/projects/p" "$w/ledger/coordination/handover"
export COORDINATOR_HOME="$w/home" CLAUDE_CONFIG_DIR="$w/config" ANTIGRAVITY_BRAIN_DIR="$w/brain"
unset SOFT_AT HARD_AT ROTATE_AT CONTEXT_WINDOW COORDINATOR_ROTATE_MAX_BLOCKS
L="$w/ledger"
git -C "$L" init -q
git -C "$L" config user.email t@t; git -C "$L" config user.name t
printf '# Ledger\n\n## Owner queue (in order)\n\n1. Approve the release.\n\n## Pending starts\n\n- none\n' >"$L/COORDINATION.md"
git -C "$L" add -A; git -C "$L" commit -qm init

pass=0; failn=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
has() { [[ "$3" == *"$2"* ]] && ok "$1" || bad "$1 (want: $2)" "$3"; }
none() { [[ -z "$2" ]] && ok "$1" || bad "$1 (want no output)" "$2"; }
lacks() { [[ "$3" != *"$2"* ]] && ok "$1" || bad "$1 (must not say: $2)" "$3"; }

# transcript <sid> <tokens> [start] [extra jsonl lines...]: an owner prompt, then the extra
# lines, then one assistant turn of that context size. start: the first record's timestamp.
transcript() {
  local sid="$1" n="$2" start="${3:-2026-01-01T00:00:00.000Z}"; shift 3 || shift $#
  {
    printf '{"type":"user","uuid":"u-owner-1","timestamp":"%s","origin":{"kind":"human"},"message":{"role":"user","content":"status?"}}\n' "$start"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '{"type":"assistant","timestamp":"2026-01-01T00:01:00Z","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":%d,"cache_creation_input_tokens":0}}}\n' $((n - 10))
  } >"$w/config/projects/p/$sid.jsonl"
}
reg() { bash "$root/plugins/coordinator/scripts/register.sh" "$1" "$L" >/dev/null; }
tp() { printf '%s' "$w/config/projects/p/$1.jsonl"; }
prompt() { # sid [prompt text]
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" "$(tp "$1")" "${2:-status?}" \
    | bash "$hooks/rotation-guard.sh" prompt; }
stop() { # sid [stop_hook_active]
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$(tp "$1")" "${2:-false}" \
    | bash "$hooks/rotation-guard.sh" stop; }

echo "--- ok, soft, hard"
reg c-ok;   transcript c-ok 120000
reg c-soft; transcript c-soft 320000
reg c-hard; transcript c-hard 460000
transcript lane-1 900000
none "ok: no prompt output"                "$(prompt c-ok)"
none "ok: no stop output"                  "$(stop c-ok)"
none "unregistered: silent at 900k"        "$(prompt lane-1)$(stop lane-1)"
out="$(prompt c-soft)"
has  "soft: the one line"                  'Coordinator at 320k / soft 300k: rotate now (procedure handover.md, then a replacement)' "$out"
has  "soft: UserPromptSubmit context"      '"hookEventName":"UserPromptSubmit","additionalContext"' "$out"
none "soft: Stop does not block"           "$(stop c-soft)"
out="$(prompt c-hard)"
has  "hard: prompt line says this turn"    'Coordinator at 460k / hard 450k: rotate in this turn' "$out"
out="$(stop c-hard)"
has  "hard: Stop blocks"                   '"decision":"block"' "$out"
has  "hard: names the handover file"       'coordination/handover/coordinator.md' "$out"
has  "hard: Remote Control way out"        'first Owner queue item of COORDINATION.md' "$out"
has  "hard: 2nd block in the turn"         '"decision":"block"' "$(stop c-hard true)"
has  "hard: 3rd block in the turn"         '"decision":"block"' "$(stop c-hard true)"
out="$(stop c-hard true)"
has  "hard: after 3 blocks, let through"   '"systemMessage"' "$out"
lacks "hard: ... and not blocked"          '"decision":"block"' "$out"
has  "hard: next turn blocks again"        '"decision":"block"' "$(stop c-hard false)"

echo "--- PROFILE Budgets"
printf '# Profile\n\n## 7. Budgets\n\n- Context, soft: 250k. Hard: 400k. Coordinator: soft 200k, hard 260k.\n' >"$L/coordination/PROFILE.md"
reg c-prof; transcript c-prof 230000
has  "profile: 230k is past the coordinator's 200k" 'Coordinator at 230k / soft 200k' "$(prompt c-prof)"
transcript c-prof 270000
has  "profile: 270k is past its hard 260k"          '"decision":"block"' "$(stop c-prof)"
chmod 000 "$L/coordination/PROFILE.md"
if [[ -r "$L/coordination/PROFILE.md" ]]; then ok "unreadable profile: skipped (running as root)"
else none "unreadable profile: kit defaults (270k is ok)" "$(prompt c-prof)"; fi
chmod 644 "$L/coordination/PROFILE.md"; rm -f "$L/coordination/PROFILE.md"

echo "--- turns the owner did not start"
reg c-peer; transcript c-peer 460000 "" '{"type":"user","uuid":"u-2","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>x</task-id>\n</task-notification>"}}'
none "task-notification turn: no block"    "$(stop c-peer)"
reg c-peer2; transcript c-peer2 460000 "" '{"type":"user","uuid":"u-2","message":{"role":"user","content":"<cross-session-message from=\"a\">PR ready: #3</cross-session-message>"}}'
none "peer message turn (no origin): no block" "$(stop c-peer2)"
none "prompt hook: task-notification text is silent" "$(prompt c-hard '<task-notification>done</task-notification>')"
reg c-tool; transcript c-tool 460000 "" '{"type":"user","uuid":"u-tool","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":"x"}]}}' '{"type":"user","uuid":"u-fb","isMeta":true,"message":{"role":"user","content":"Stop hook feedback: x"}}'
has  "tool results and hook feedback keep the owner turn" '"decision":"block"' "$(stop c-tool)"

echo "--- background subagents"
launch='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_A","name":"Agent","input":{"subagent_type":"coordinator:reviewer","description":"Review PR 12","run_in_background":true}}]}}'
launched='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":[{"type":"text","text":"Async agent launched successfully.\nagentId: a123 (internal ID)"}]}]}}'
reg c-sub; transcript c-sub 460000 "" "$launch" "$launched"
out="$(prompt c-sub)"
has  "subagent: prompt line says wait"     'first wait for the background subagent(s) still running: coordinator:reviewer: Review PR 12' "$out"
out="$(stop c-sub)"
has  "subagent: first stop blocks"         '"decision":"block"' "$out"
has  "subagent: block names it"            'coordinator:reviewer: Review PR 12' "$out"
has  "subagent: handover alternative"      'running: <agent>, <task>' "$out"
out="$(stop c-sub true)"
has  "subagent: next stop let through"     'Stop let through to wait for them' "$out"
lacks "subagent: ... not blocked"          '"decision":"block"' "$out"
reg c-soft-sub; transcript c-soft-sub 320000 "" "$launch" "$launched"
has  "subagent at soft: wait line"         'rotate now (procedure handover.md, then a replacement); first wait for' "$(prompt c-soft-sub)"
notif='{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a123</task-id>\n<status>completed</status>\n</task-notification>"}'
reg c-subdone; transcript c-subdone 460000 "" "$launch" "$launched" "$notif"
lacks "subagent reported: no wait line"    'first wait' "$(prompt c-subdone)"
has  "subagent reported: plain block"      '"decision":"block"' "$(stop c-subdone true)"
fg='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"Review: approve"}]}}'
reg c-fg; transcript c-fg 320000 "" "$launch" "$fg"
lacks "foreground subagent: not running"   'first wait' "$(prompt c-fg)"

echo "--- merge in flight"
reg c-merge; transcript c-merge 460000
. "$hooks/lib.sh"; pending_add c-merge o/r#7
out="$(stop c-merge)"
has  "pending Next: let through once"      'merge in flight (pending Next for o/r#7)' "$out"
lacks "pending Next: ... not blocked"      '"decision":"block"' "$out"
has  "pending Next: same turn still through" 'merge in flight' "$(stop c-merge)"
transcript c-merge 460000 "" '{"type":"user","uuid":"u-owner-2","origin":{"kind":"human"},"message":{"role":"user","content":"next?"}}'
has  "pending Next: next owner turn blocks" '"decision":"block"' "$(stop c-merge)"
ciw='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_C","name":"Bash","input":{"command":"bash /x/scripts/ci-watch.sh o/r 7 abc","run_in_background":true}}]}}'
ciwr='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_C","content":"Command running in background with ID: bxyz. Output is being written to: /tmp/x"}]}}'
reg c-ci; transcript c-ci 460000 "" "$ciw" "$ciwr"
has  "ci-watch running: let through once"  'ci-watch running' "$(stop c-ci)"
reg c-cidone; transcript c-cidone 460000 "" "$ciw" "$ciwr" '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>bxyz</task-id>\n<tool-use-id>toolu_C</tool-use-id>\n</task-notification>"}}' '{"type":"user","uuid":"u-owner-3","origin":{"kind":"human"},"message":{"role":"user","content":"go"}}'
has  "ci-watch ended: blocks"              '"decision":"block"' "$(stop c-cidone)"

echo "--- the ways out"
reg c-ho; transcript c-ho 460000
has  "before the handover: blocks"         '"decision":"block"' "$(stop c-ho)"
echo "# Handover" >"$L/coordination/handover/coordinator.md"
git -C "$L" add -A; git -C "$L" commit -qm handover
none "handover committed: stop allowed"    "$(stop c-ho)"
reg c-old; transcript c-old 460000 "2099-01-01T00:00:00.000Z"
has  "handover from before the session does not count" '"decision":"block"' "$(stop c-old)"
git -C "$L" rm -q "$L/coordination/handover/coordinator.md"; git -C "$L" commit -qm rm
none "handover deleted again: not counted" "$(transcript c-ho2 460000; reg c-ho2; stop c-ho2 | grep -v '"decision":"block"' || true)"
reg c-rc; transcript c-rc 460000 "2099-01-01T00:00:00.000Z"
printf '# Ledger\n\n## Owner queue (in order)\n\n1. Rotate the coordinator (460k, past hard): start a fresh session from the handover.\n2. Approve the release.\n' >"$L/COORDINATION.md"
has  "owner-queue line not committed: blocks"  '"decision":"block"' "$(stop c-rc)"
git -C "$L" commit -qam rotate
has  "owner-queue line before the session: blocks" '"decision":"block"' "$(stop c-rc)"
transcript c-rc 460000
none "Remote Control: rotation first in the owner queue" "$(stop c-rc)"
printf '# Ledger\n\n## Owner queue (in order)\n\n1. Approve the release.\n2. Rotate the coordinator.\n' >"$L/COORDINATION.md"
git -C "$L" commit -qam second
has  "rotation not first in the queue: blocks" '"decision":"block"' "$(stop c-rc)"

echo "--- fail-open"
reg c-garb; printf 'not json\n{"type":"assistant"\n' >"$(tp c-garb)"
none "garbage transcript: silent"          "$(prompt c-garb)$(stop c-garb)"
reg c-none
none "no transcript: silent"               "$(printf '{"session_id":"c-none","hook_event_name":"Stop"}' | bash "$hooks/rotation-guard.sh" stop)"
nopy="$w/nopy"; mkdir -p "$nopy"
for c in bash cat sed head awk git grep mkdir rm env tr paste dirname date jq; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$nopy/$c"
done
none "no python3: silent"                  "$(printf '{"session_id":"c-hard","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$(tp c-hard)" | PATH="$nopy" bash "$hooks/rotation-guard.sh" stop)"
none "bad session id: silent"              "$(printf '{"session_id":"../x","hook_event_name":"Stop"}' | bash "$hooks/rotation-guard.sh" stop)"
rm -rf "$w/gone"; mkdir "$w/gone"; bash "$root/plugins/coordinator/scripts/register.sh" c-gone "$w/gone" >/dev/null 2>&1; rmdir "$w/gone"; transcript c-gone 460000
none "ledger folder gone: silent"          "$(stop c-gone)"
none "unknown event: silent"               "$(printf '{"session_id":"c-hard","hook_event_name":"PreToolUse"}' | bash "$hooks/rotation-guard.sh")"
COORDINATOR_NO_JQ=1 has "python3 JSON path: same block" '"decision":"block"' "$(COORDINATOR_NO_JQ=1 stop c-hard)"

echo "--- Antigravity"
agt() { # cid tokens
  mkdir -p "$w/brain/$1/.system_generated/logs"
  { printf '{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"hi"}\n'
    printf '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","input_tokens":10,"cache_read_tokens":%d}\n' $(($2 - 10)); } \
    >"$w/brain/$1/.system_generated/logs/transcript.jsonl"
}
reg ag-ok; agt ag-ok 100000; reg ag-soft; agt ag-soft 320000; reg ag-hard; agt ag-hard 460000
agp() { printf '{"conversationId":"%s","hookEventName":"PreInvocation","lastUserInput":"status?"}' "$1" | bash "$hooks/rotation-guard.sh" prompt; }
ags() { printf '{"conversationId":"%s","hookEventName":"Stop","continuationActive":%s}' "$1" "${2:-false}" | bash "$hooks/rotation-guard.sh" stop; }
has  "AG ok: neutral prompt answer"        '{}' "$(agp ag-ok)"
has  "AG ok: neutral stop answer"          '{"decision":"stop"}' "$(ags ag-ok)"
out="$(agp ag-soft)"
has  "AG soft: same line, injectSteps"     '{"injectSteps":[{"systemMessage":{"systemMessage":"Coordinator at 320k / soft 300k: rotate now (procedure handover.md, then a replacement)"}}]}' "$out"
has  "AG hard: Stop continues (blocks)"    '"decision":"continue"' "$(ags ag-hard)"
mkdir -p "$L/coordination/handover"; echo "# Handover" >"$L/coordination/handover/coordinator.md"; git -C "$L" add -A; git -C "$L" commit -qm ho2
has  "AG hard + handover since registration: stop" '{"decision":"stop"}' "$(ags ag-hard)"
git -C "$L" rm -q "$L/coordination/handover/coordinator.md"; git -C "$L" commit -qm rm2
reg ag-hard2; agt ag-hard2 460000; pending_add ag-hard2 o/r#9
chain() { printf '{"conversationId":"%s","hookEventName":"%s","lastUserInput":"PR ready: https://github.com/o/r/pull/9","continuationActive":false}' "$1" "$2" | bash "$hooks/ag-chain.sh" "$3" "${@:4}"; }
out="$(chain ag-hard2 Stop stop next-guard.sh rotation-guard.sh:stop)"
has  "ag-chain stop: next-guard's block wins" 'still need the author told' "$out"
has  "ag-chain stop: one decision"         '"decision":"continue"' "$out"
has  "ag-chain stop: rotation block when next-guard is quiet" 'rotate in this turn' "$(chain ag-hard Stop stop next-guard.sh rotation-guard.sh:stop)"
has  "ag-chain stop: neutral when all quiet" '{"decision":"stop"}' "$(chain ag-ok Stop stop next-guard.sh rotation-guard.sh:stop)"
out="$(chain ag-soft PreInvocation prompt ci-watch-reminder.sh rotation-guard.sh:prompt)"
has  "ag-chain prompt: CI watch step"      'ci-watch.sh' "$out"
has  "ag-chain prompt: rotation step"      'rotate now' "$out"
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert len(d["injectSteps"]) == 2' "$out" && ok "ag-chain prompt: valid JSON, two steps" || bad "ag-chain prompt JSON" "$out"
has  "ag-chain prompt: {} when quiet"      '{}' "$(printf '{"conversationId":"ag-ok","hookEventName":"PreInvocation","lastUserInput":"hi"}' | bash "$hooks/ag-chain.sh" prompt ci-watch-reminder.sh rotation-guard.sh:prompt)"
none "ag-chain: unknown hook names skipped" "$(printf '{}' | bash "$hooks/ag-chain.sh" prompt '../x.sh' | tr -d '{}\n')"

echo "$pass passed, $failn failed"
[[ $failn -eq 0 ]]
