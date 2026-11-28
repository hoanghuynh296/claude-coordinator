#!/usr/bin/env bash
# report-guard.sh and report-sent.sh (#10): an agent of an opted-in unit cannot end a turn while
# its branch's open PR head was never reported "PR ready:". A local unit repo with a bare origin,
# a fake gh (FAKE_PR: "<n> <sha>" or empty; FAKE_GH_FAIL=1 fails; FAKE_GH_SLEEP delays; every
# call is logged), fake transcripts.
# Covers: opt-in (install-guards --agent); coordinator, owner and unregistered sessions (also with
# CLAUDE.md / AGENTS.md attachments and tool results naming the coordinator); integration and
# release branches; no PR; the head SHA rule; blocked / handover / draft reports and the pushed
# head they saw; a new head after a report; no gh call once reported and pushed; the block cap;
# fail-open; Antigravity payloads and ag-chain.sh (stop and post). Temporary COORDINATOR_HOME.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
plugin="$root/plugins/coordinator"; hooks="$plugin/hooks"
w="$root/tests/.work/report"; rm -rf "${w:?}"; mkdir -p "$w/config/projects/p" "$w/bin" "$w/ledger"
export COORDINATOR_HOME="$w/home" CLAUDE_CONFIG_DIR="$w/config" ANTIGRAVITY_BRAIN_DIR="$w/brain"
unset COORDINATOR_REPORT_MAX_BLOCKS COORDINATOR_REPORT_GUARD FAKE_GH_FAIL FAKE_GH_SLEEP
touch "$w/ledger/COORDINATION.md"

git init -q --bare "$w/origin.git"
U="$w/unit"; mkdir -p "$U"
git -C "$U" init -q -b feat; git -C "$U" config user.email t@t; git -C "$U" config user.name t
git -C "$U" remote add origin "$w/origin.git"
echo x >"$U/a"; git -C "$U" add -A; git -C "$U" commit -qm one
git -C "$U" push -qu origin feat 2>/dev/null
U="$(cd "$U" && pwd -P)"
H="$(git -C "$U" rev-parse HEAD)"; S="${H:0:7}"
O="$w/other"; mkdir -p "$O"; git -C "$O" init -q -b feat   # not opted in
O="$(cd "$O" && pwd -P)"

cat >"$w/bin/gh" <<'GH'
#!/usr/bin/env bash
echo call >>"${FAKE_GH_LOG:-/dev/null}"
[[ -n "${FAKE_GH_SLEEP:-}" ]] && sleep "$FAKE_GH_SLEEP"
[[ -n "${FAKE_GH_FAIL:-}" ]] && exit 1
printf '%s\n' "${FAKE_PR:-}"
GH
chmod +x "$w/bin/gh"; export COORDINATOR_GH="$w/bin/gh" FAKE_GH_LOG="$w/gh-calls"
calls() { cat "$FAKE_GH_LOG" 2>/dev/null | wc -l | tr -d ' '; }

pass=0; failn=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
has() { [[ "$3" == *"$2"* ]] && ok "$1" || bad "$1 (want: $2)" "$3"; }
none() { [[ -z "$2" ]] && ok "$1" || bad "$1 (want no output)" "$2"; }
eq()  { [[ "$3" == "$2" ]] && ok "$1" || bad "$1 (want: $2)" "$3"; }
lacks() { [[ "$3" != *"$2"* ]] && ok "$1" || bad "$1 (must not say: $2)" "$3"; }

line='Your coordinator is the session **Coordinator: Demo**; you report to it by message.'
brief() { printf '{"type":"user","message":{"role":"user","content":"# Agent brief\\n%s"}}\n' "$line" >"$w/config/projects/p/$1.jsonl"; }
tp() { printf '%s' "$w/config/projects/p/$1.jsonl"; }
stop() { # sid [stop_hook_active] [dir]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
    "$1" "$(tp "$1")" "${3:-$U}" "${2:-false}" | bash "$hooks/report-guard.sh"; }
send() { # sid message (JSON-escaped)
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"Coordinator: Demo","message":"%s"}}' \
    "$1" "$U" "$2" | bash "$hooks/report-sent.sh"; }

echo "--- opt-in"
out="$(bash "$plugin/scripts/install-guards.sh" --agent Demo "$U")"
has  "install-guards --agent reports it"     'agent report guard on' "$out"
eq   "install-guards --agent sets reportTo"  'Coordinator: Demo' "$(git -C "$U" config --get coordinator.reportTo)"
bash "$plugin/scripts/install-guards.sh" --agent "Coordinator: Demo" "$U" >/dev/null
eq   "--agent takes the full name too"       'Coordinator: Demo' "$(git -C "$U" config --get coordinator.reportTo)"

export FAKE_PR="12 $H"
brief a1
echo "--- silent cases"
brief plain1; none "repo not opted in: silent"   "$(stop plain1 false "$O")"
printf '{"type":"user","message":{"role":"user","content":"fix the typo"}}\n' >"$(tp owner1)"
none "owner session (no brief, no report): silent" "$(stop owner1)"
# Owner session in a unit whose CLAUDE.md / AGENTS.md names the coordinator: Claude Code copies
# them into the transcript as attachments and meta messages; tool results can quote them too.
{
  printf '{"type":"attachment","attachment":{"type":"nested_memory","content":"AGENTS.md: %s Report to \\"Coordinator: Demo\\"."}}\n' "$line"
  printf '{"type":"user","isMeta":true,"message":{"role":"user","content":"<system-reminder>CLAUDE.md: %s</system-reminder>"}}\n' "$line"
  printf '{"type":"user","message":{"role":"user","content":"fix the build"}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"%s"}]}}\n' "$line"
  printf '{"type":"user","isSidechain":true,"message":{"role":"user","content":"%s"}}\n' "$line"
  printf '{"type":"user","message":{"role":"user","content":"Mentions Coordinator: Demo by name only."}}\n'
} >"$(tp owner2)"
none "owner session, AGENTS.md / CLAUDE.md / tool result name it: silent" "$(stop owner2)"
printf '{"type":"user","message":{"role":"user","content":"Your coordinator is the session **Coordinator: Demo Two**."}}\n' >"$(tp other1)"
none "brief of another coordinator: silent"  "$(stop other1)"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Your coordinator is the session Coordinator: Demo; report by message."}]}}\n' >"$(tp plain2)"
has  "plain (unbolded) brief line in a text block: agent" '"decision":"block"' "$(stop plain2)"
none "no transcript, no report: silent"      "$(stop ghost1)"
bash "$plugin/scripts/register.sh" coord-1 "$w/ledger" >/dev/null; brief coord-1
none "registered coordinator: silent"        "$(stop coord-1)"
none "no open PR: silent"                    "$(FAKE_PR="" stop a1)"
none "gh fails: silent (fail open)"          "$(FAKE_GH_FAIL=1 stop a1)"
none "gh times out: silent (fail open)"      "$(FAKE_GH_SLEEP=3 COORDINATOR_REPORT_GH_TIMEOUT=1 stop a1)"
none "gh missing: silent"                    "$(COORDINATOR_GH="$w/bin/none" stop a1)"
none "COORDINATOR_REPORT_GUARD=off: silent"  "$(COORDINATOR_REPORT_GUARD=off stop a1)"
git -C "$U" checkout -q --detach
none "detached HEAD: silent"                 "$(stop a1)"
for b in develop main release/1.2 backmerge/x trunk; do
  git -C "$U" checkout -q -b "$b" feat
  [[ "$b" == trunk ]] && git -C "$U" config coordinator.protectedBranches "main trunk"
  none "agent on $b with an open (release) PR: silent" "$(stop a1)"
done
git -C "$U" checkout -q feat
rm -f "$FAKE_GH_LOG"

echo "--- block, report, cap"
out="$(stop a1)"
has  "unreported PR: blocks"                 '"decision":"block"' "$out"
has  "names PR and head"                     "PR #12 (head $S)" "$out"
has  "names the coordinator"                 'Coordinator: Demo' "$out"
has  "asks for a PR comment too"             'PR comment' "$out"
has  "gives the first line"                  "PR ready: #12 $S" "$out"
has  "2nd block in the turn"                 '"decision":"block"' "$(stop a1 true)"
has  "3rd block in the turn"                 '"decision":"block"' "$(stop a1 true)"
out="$(stop a1 true)"
has  "cap: 4th stop allowed with a warning"  '"systemMessage"' "$out"
has  "cap: warning names the head"           "head $S is still not reported" "$out"
has  "next turn blocks again"                '"decision":"block"' "$(stop a1)"
none "progress note is no report"            "$(send a1 "working on it, $S pushed")"
has  "progress note: still blocks"           '"decision":"block"' "$(stop a1)"
send a1 "PR ready: #12 ${H:0:9}, CI pending, local gate green\\nContext: 80k"
n0="$(calls)"
none "PR ready naming the head: silent"      "$(stop a1)"
none "... also on a later stop"              "$(stop a1 true)"
eq   "reported and pushed: no gh call"       "$n0" "$(calls)"

echo "--- other report kinds and the pushed head"
brief a2
send a2 "PR ready: #12 deadbee, CI green"
has  "PR ready naming another SHA: blocks"   '"decision":"block"' "$(stop a2)"
brief a3; send a3 "blocked: needs a decision on the schema"
none "blocked report while the head was pushed: silent" "$(stop a3)"
brief a4; send a4 "Handover written: coordination/handover/unit.md"
none "handover report: silent"               "$(stop a4)"
brief a5; send a5 "Draft ready: https://x/draft"
none "draft report: silent"                  "$(stop a5)"
brief a6; send a6 "  \\n  PR ready: #12 $S"
none "first non-empty line counts"           "$(stop a6)"
brief a8; send a8 "Status: handover later, still working"
has  "handover not at the start: no report"  '"decision":"block"' "$(stop a8)"
# A fix committed, then "blocked:", then pushed: the blocked report saw the old pushed head.
echo y >>"$U/a"; git -C "$U" commit -qam two; H2="$(git -C "$U" rev-parse HEAD)"
brief a7; send a7 "blocked: waiting for the API key"
git -C "$U" push -q origin feat 2>/dev/null
export FAKE_PR="12 $H2"
has  "blocked before the push, head pushed after: blocks" "head ${H2:0:7}" "$(stop a7)"
has  "new head after PR ready: blocks"       "head ${H2:0:7}" "$(stop a1)"
has  "new head after blocked: blocks"        '"decision":"block"' "$(stop a3)"
send a1 "PR ready: #12 ${H2:0:7}, CI pending"
none "re-report of the new head: silent"     "$(stop a1)"
send a7 "blocked: still waiting for the API key"
none "blocked again after the push: silent"  "$(stop a7)"
# An unpushed local commit after the report: gh is asked, the PR head is still the reported one.
echo z >>"$U/a"; git -C "$U" commit -qam three
n0="$(calls)"
none "unpushed commit after report: silent"  "$(stop a1)"
eq   "unpushed commit: gh asked"             "$((n0 + 1))" "$(calls)"
git -C "$U" push -q origin feat 2>/dev/null; H3="$(git -C "$U" rev-parse HEAD)"
none "report-sent: no output on Claude Code" "$(send a1 "PR ready: #12 $S")"
send coord-1 "PR ready: #12 $S"
[[ ! -f "$COORDINATOR_HOME/state/coord-1/reports" ]] && ok "coordinator messages are not recorded" || bad "coordinator report recorded"
export FAKE_PR="12 $H3"

echo "--- Antigravity"
agstop() { printf '{"conversationId":"%s","cwd":"%s","hookEventName":"Stop","continuationActive":%s}' "$1" "$U" "${2:-false}" | bash "$hooks/report-guard.sh"; }
mkdir -p "$w/brain/ag1/.system_generated/logs" "$w/brain/ag3/.system_generated/logs"
printf '{"type":"USER_INPUT","source":"USER_EXPLICIT","content":"<USER_REQUEST>\\n%s\\n</USER_REQUEST>"}\n' "$line" >"$w/brain/ag1/.system_generated/logs/transcript.jsonl"
printf '{"type":"SYSTEM_MESSAGE","content":"AGENTS.md: %s"}\n{"type":"USER_INPUT","content":"fix it"}\n' "$line" >"$w/brain/ag3/.system_generated/logs/transcript.jsonl"
out="$(agstop ag1)"
has  "AG unreported: decision continue"      '"decision":"continue"' "$out"
has  "AG names the head"                     "head ${H3:0:7}" "$out"
eq   "AG owner session (rules only in a system message): stop" '{"decision":"stop"}' "$(agstop ag3)"
eq   "AG not opted in: stop"                 '{"decision":"stop"}' "$(printf '{"conversationId":"ag1","cwd":"%s","hookEventName":"Stop"}' "$O" | bash "$hooks/report-guard.sh")"
eq   "AG coordinator: stop"                  '{"decision":"stop"}' "$(printf '{"conversationId":"coord-1","cwd":"%s","hookEventName":"Stop"}' "$U" | bash "$hooks/report-guard.sh")"
agstop ag1 true >/dev/null; agstop ag1 true >/dev/null
has  "AG cap: stop with reason"              '"decision":"stop","reason"' "$(agstop ag1 true)"
agsend() { printf '{"conversationId":"%s","cwd":"%s","hookEventName":"PostToolUse","toolCall":{"id":"t1","name":"send_message","args":{"Recipient":"Coordinator: Demo","Message":"%s"}}}' "$1" "$U" "$2"; }
eq   "AG ag-chain post: {}"                  '{}' "$(agsend ag1 "PR ready: #12 ${H3:0:7}, CI pending" | bash "$hooks/ag-chain.sh" post next-sent.sh report-sent.sh)"
eq   "AG after report: stop"                 '{"decision":"stop"}' "$(agstop ag1)"
mkdir -p "$w/brain/ag2/.system_generated/logs"; cp "$w/brain/ag1/.system_generated/logs/transcript.jsonl" "$w/brain/ag2/.system_generated/logs/"
out="$(printf '{"conversationId":"ag2","cwd":"%s","hookEventName":"Stop","continuationActive":false}' "$U" | bash "$hooks/ag-chain.sh" stop next-guard.sh rotation-guard.sh:stop report-guard.sh)"
has  "ag-chain stop: report-guard block wins" 'is open and not reported' "$out"
python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$out" && ok "ag-chain stop: valid JSON" || bad "ag-chain JSON" "$out"
out="$(printf '{"conversationId":"coord-1","hookEventName":"PostToolUse","toolCall":{"id":"t","name":"send_message","args":{"Message":"x"}}}' | bash "$hooks/ag-chain.sh" post next-sent.sh report-sent.sh)"
eq   "ag-chain post: {} when all quiet"      '{}' "$out"
lacks "Claude reason has no AG decision"     '"decision":"continue"' "$(stop a2)"

echo "--- wiring"
python3 -I - "$plugin" <<'PY' && ok "wired: Claude Stop + PostToolUse, Antigravity Stop chain + post chain" || bad "report guard wiring"
import json, os, sys
p = sys.argv[1]
h = json.load(open(os.path.join(p, "hooks", "hooks.json")))["hooks"]
assert any("report-guard.sh" in x["command"] for e in h["Stop"] for x in e["hooks"])
m = [e["matcher"] for e in h["PostToolUse"] if any("report-sent.sh" in x["command"] for x in e["hooks"])]
assert m and "SendMessage" in m[0] and "mcp__ccd_session_mgmt__send_message" in m[0]
a = json.load(open(os.path.join(p, "hooks.json")))["coordinator-hooks"]
st = " ".join(x["command"] for x in a["Stop"])
assert "ag-chain.sh stop" in st and "report-guard.sh" in st and "next-guard.sh" in st
post = [x["command"] for e in a["PostToolUse"] if "send_message" in e["matcher"] for x in e["hooks"]]
assert post and "ag-chain.sh post" in post[0] and "next-sent.sh" in post[0] and "report-sent.sh" in post[0]
PY

echo "---"
rm -rf "$w"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
