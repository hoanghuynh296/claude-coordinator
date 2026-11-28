#!/usr/bin/env bash
# Runtime parity (#55): every hook in hooks/ gets an Antigravity payload and must give exactly one
# line of JSON in the shape Antigravity reads - its answer, or its documented silence ({},
# {"decision":"allow"}, {"decision":"stop"}). A hook added without a case here fails the test, and
# the two hooks.json files must run the same hooks (Antigravity adds only ag-chain.sh). Where the
# runtimes differ on purpose (SKILL.md "What each runtime enforces"), the test pins the difference.
# Temporary COORDINATOR_HOME and fake gh; the real ones are untouched.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
plugin="$root/plugins/coordinator"; hooks="$plugin/hooks"
w="$root/tests/.work/parity"; rm -rf "${w:?}"; mkdir -p "$w/ledger/coordination" "$w/unit/src" "$w/plain" "$w/gh"
export COORDINATOR_HOME="$w/home" ANTIGRAVITY_BRAIN_DIR="$w/brain" CLAUDE_CONFIG_DIR="$w/config"
export COORDINATOR_AG_LINK="$w/no-link" COORDINATOR_CC_INSTALLED="$w/none.json"
unset SOFT_AT HARD_AT ROTATE_AT CONTEXT_WINDOW COORDINATOR_GH_LOGIN
touch "$w/ledger/COORDINATION.md"
L="$(cd "$w/ledger" && pwd -P)"; U="$(cd "$w/unit" && pwd -P)"; PL="$(cd "$w/plain" && pwd -P)"
bash "$plugin/scripts/register.sh" ag-coord "$L" "$U" >/dev/null
bash "$plugin/scripts/register.sh" cc-coord "$L" "$U" >/dev/null
export FAKE_GH_DIR="$w/gh"
cat >"$w/fake-gh" <<'GH'
#!/usr/bin/env bash
# gh pr view <N> ... -R owner/repo: every PR is MERGED, head feature/x, author dev
repo=o/r; n=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in -R|--repo) repo="${args[$((i+1))]}"; i=$((i+1)) ;; [0-9]*) [[ -z "$n" ]] && n="${args[$i]}" ;; esac
done
printf '{"state":"MERGED","url":"https://github.com/%s/pull/%s","headRefName":"feature/x","author":{"login":"dev"}}\n' "$repo" "$n"
GH
chmod +x "$w/fake-gh"; export COORDINATOR_GH="$w/fake-gh"

pass=0; failn=0; covered=" "
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
# ag <name> <hook> <expected: exact JSON | ~substring> <payload> [hook args...]
# The output must be one line of one JSON object; then it must equal (or contain) the expectation.
ag() {
  local name="$1" hook="$2" want="$3" payload="$4"; shift 4
  covered="$covered$hook "
  local out; out="$(printf '%s' "$payload" | bash "$hooks/$hook" "$@" 2>/dev/null)" || { bad "$name: $hook failed"; return; }
  if ! python3 -I -c 'import json,sys; s=sys.argv[1]; assert s.count("\n")==0 and isinstance(json.loads(s), dict)' "$out" 2>/dev/null; then
    bad "$name: not one line of one JSON object" "$out"; return
  fi
  if [[ "$want" == "~"* ]]; then [[ "$out" == *"${want#\~}"* ]] && ok "$name" || bad "$name (want: ${want#\~})" "$out"
  else [[ "$out" == "$want" ]] && ok "$name" || bad "$name (want exactly: $want)" "$out"; fi
}
cc() { # <name> <hook> <expected: EMPTY | ~substring> <payload>: the Claude Code side of a difference
  local out; out="$(printf '%s' "$4" | bash "$hooks/$2" 2>/dev/null)" || true
  if [[ "$3" == EMPTY ]]; then [[ -z "$out" ]] && ok "$1" || bad "$1 (want no output)" "$out"
  else [[ "$out" == *"${3#\~}"* ]] && ok "$1" || bad "$1 (want: ${3#\~})" "$out"; fi
}
pend() { awk '{printf "%s ", $1}' "$COORDINATOR_HOME/state/$1/pending-next" 2>/dev/null || true; }

echo "--- the two hooks.json files run the same hooks"
python3 -I - "$hooks/hooks.json" "$plugin/hooks.json" <<'PY' && ok "Claude Code and Antigravity hooks.json name the same hooks (+ ag-chain.sh)" || bad "hooks.json files disagree"
import json, re, sys
def scripts(path):
    found = set()
    def walk(v):
        if isinstance(v, dict):
            for x in v.values(): walk(x)
        elif isinstance(v, list):
            for x in v: walk(x)
        elif isinstance(v, str):
            found.update(re.findall(r"([a-z-]+\.sh)", v))
    walk(json.load(open(path)))
    return found
cc, ag = scripts(sys.argv[1]), scripts(sys.argv[2])
if ag - cc != {"ag-chain.sh"} or cc - ag:
    sys.exit(f"Claude Code only: {sorted(cc - ag)}; Antigravity only: {sorted(ag - cc)}")
PY

echo "--- PreToolUse: coordinator-guard.sh"
edit() { printf '{"conversationId":"%s","cwd":"%s","artifactDirectoryPath":"/private/tmp/ag-a","hookEventName":"PreToolUse","toolCall":{"id":"t","name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"x"}}%s}' "$1" "$U" "$2" "${3:-}"; }
ag "guard: ledger file -> allow"         coordinator-guard.sh '{"decision":"allow"}' "$(edit ag-coord "$L/COORDINATION.md")"
ag "guard: unit code -> deny + reason"   coordinator-guard.sh '~{"decision":"deny","reason":"Coordinator guard:' "$(edit ag-coord "$U/src/app.ts")"
ag "guard: unregistered -> allow"        coordinator-guard.sh '{"decision":"allow"}' "$(edit ag-other "$U/src/app.ts")"
# Claude Code only: a oneoff-builder subagent writes in its own worktree; Antigravity's payload
# names no subagent, so the same write is judged as the coordinator's and denied.
git -C "$U" init -q; git -C "$U" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$U" worktree add -q "$U/.claude/worktrees/builder-docs" -b builder-docs
B="$U/.claude/worktrees/builder-docs/src/a.ts"
ag "guard: builder worktree on Antigravity -> deny (builder rule is Claude Code only)" coordinator-guard.sh '~"decision":"deny"' "$(edit ag-coord "$B" ',"agentType":"coordinator:oneoff-builder"')"
cc "guard: builder worktree on Claude Code -> allow" coordinator-guard.sh EMPTY \
  "$(printf '{"session_id":"cc-coord","agent_id":"b1","agent_type":"coordinator:oneoff-builder","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$U" "$B")"

echo "--- Stop / PostToolUse send_message: report-guard.sh, report-sent.sh (silent outside an opted-in agent unit; full cases in report-guard-test.sh)"
ag "report-guard: coordinator -> stop"     report-guard.sh '{"decision":"stop"}' "$(printf '{"conversationId":"ag-coord","cwd":"%s","hookEventName":"Stop","continuationActive":false}' "$U")"
ag "report-sent: no report -> {}"          report-sent.sh  '{}' "$(printf '{"conversationId":"ag-other","cwd":"%s","hookEventName":"PostToolUse","toolCall":{"id":"t","name":"send_message","args":{"Recipient":"Coordinator: Demo","Message":"hello"}}}' "$U")"

echo "--- SessionStart: session-start.sh"
start() { printf '{"conversationId":"%s","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$1" "$2"; }
ag "session-start: registered -> injectSteps" session-start.sh '~{"injectSteps":[{"systemMessage":{"systemMessage":"You are the COORDINATOR' "$(start ag-coord "$PL")"
ag "session-start: plain folder -> {}"        session-start.sh '{}' "$(start ag-other "$PL")"
mkdir -p "$w/aglink"; printf '{\n  "version": "99.0.0"\n}\n' >"$w/aglink/plugin.json"
COORDINATOR_AG_LINK="$w/aglink" ag "session-start: newer kit at the link -> one rotate line in the same JSON" session-start.sh '~99.0.0 is installed: rotate this session at the next safe point' "$(start ag-coord "$PL")"
echo "--- PreInvocation: kit-notice.sh (rotate line once per newer kit; hooks-test.sh has the in-place install)"
pre_kn() { printf '{"conversationId":"%s","hookEventName":"PreInvocation"}' "$1"; }
ag "kit-notice: session SessionStart never recorded -> {}" kit-notice.sh '{}' "$(pre_kn ag-unseen)"
ag "kit-notice: rotate line already given at start -> {}"  kit-notice.sh '{}' "$(pre_kn ag-coord)"
printf '%s' "$(start ag-coord2 "$L")" | COORDINATOR_AG_LINK="$w/no-link" bash "$hooks/session-start.sh" >/dev/null
COORDINATOR_AG_LINK="$w/aglink" ag "kit-notice: newer kit installed since the start -> injectSteps" kit-notice.sh '~{"injectSteps":[{"systemMessage":{"systemMessage":"Coordinator kit ' "$(pre_kn ag-coord2)"

echo "--- PostToolUse run_command: merge-reminder.sh (silent on Antigravity, records the merge)"
cmd() { printf '{"conversationId":"%s","cwd":"%s","hookEventName":"PostToolUse","toolCall":{"id":"t","name":"run_command","args":{"CommandLine":"%s"}}}' "$1" "$w" "$2"; }
ag "merge-reminder: merge -> {} (documented silence)" merge-reminder.sh '{}' "$(cmd ag-coord 'gh pr merge 12 -R o/r --merge')"
[[ "$(pend ag-coord)" == "o/r#12 " ]] && ok "merge-reminder: the merge is recorded anyway" || bad "merge not recorded" "$(pend ag-coord)"
ag "merge-reminder: other command -> {}"  merge-reminder.sh '{}' "$(cmd ag-coord 'git status')"
ag "merge-reminder: unregistered -> {}"   merge-reminder.sh '{}' "$(cmd ag-other 'gh pr merge 12 -R o/r')"
cc "merge-reminder: Claude Code shows the reminder" merge-reminder.sh '~merged. Next:' \
  "$(printf '{"session_id":"cc-coord","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"gh pr merge 12 -R o/r --merge"}}' "$w")"

echo "--- Stop: next-guard.sh"
stopp() { printf '{"conversationId":"%s","hookEventName":"Stop","continuationActive":false}' "$1"; }
ag "next-guard: pending Next -> continue + reason" next-guard.sh '~{"decision":"continue","reason":' "$(stopp ag-coord)"

echo "--- PostToolUse send_message: next-sent.sh (silent on Antigravity, clears the pending Next)"
send() { printf '{"conversationId":"%s","hookEventName":"PostToolUse","toolCall":{"id":"t","name":"send_message","args":{"Recipient":"w1","Message":"%s"}}}' "$1" "$2"; }
ag "next-sent: Next sent -> {} (documented silence)" next-sent.sh '{}' "$(send ag-coord 'PR #12 merged. Next: #50')"
[[ -z "$(pend ag-coord)" ]] && ok "next-sent: the pending Next is cleared anyway" || bad "not cleared" "$(pend ag-coord)"
ag "next-sent: other message -> {}" next-sent.sh '{}' "$(send ag-coord 'hello')"
ag "next-guard: nothing pending -> stop"   next-guard.sh '{"decision":"stop"}' "$(stopp ag-coord)"
ag "next-guard: unregistered -> stop"      next-guard.sh '{"decision":"stop"}' "$(stopp ag-other)"

echo "--- PreInvocation: ci-watch-reminder.sh"
pre() { printf '{"conversationId":"%s","hookEventName":"PreInvocation","lastUserInput":"%s","continuationActive":false}' "$1" "$2"; }
ag "ci-watch-reminder: PR ready -> injectSteps" ci-watch-reminder.sh '~{"injectSteps":[{"systemMessage":{"systemMessage":"Coordinator: an agent reported' "$(pre ag-coord 'PR ready: https://github.com/o/r/pull/12 head abc1234')"
ag "ci-watch-reminder: other input -> {}"       ci-watch-reminder.sh '{}' "$(pre ag-coord 'status?')"
ag "ci-watch-reminder: unregistered -> {}"      ci-watch-reminder.sh '{}' "$(pre ag-other 'PR ready: #3')"

echo "--- PreInvocation and Stop: rotation-guard.sh (no transcript: fails open)"
ag "rotation-guard prompt: -> {}"      rotation-guard.sh '{}' "$(pre ag-coord 'status?')" prompt
ag "rotation-guard stop: -> stop"      rotation-guard.sh '{"decision":"stop"}' "$(stopp ag-coord)" stop
ag "rotation-guard unregistered: -> {}" rotation-guard.sh '{}' "$(pre ag-other 'status?')" prompt

echo "--- ag-chain.sh with the commands of Antigravity's hooks.json"
chain_cmd() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["coordinator-hooks"][sys.argv[2]]; print(d[0]["command"].split("ag-chain.sh ",1)[1])' "$plugin/hooks.json" "$1"; }
# shellcheck disable=SC2046
ag "ag-chain PreInvocation: PR ready -> one injectSteps" ag-chain.sh '~{"injectSteps":[{"systemMessage"' "$(pre ag-coord 'PR ready: https://github.com/o/r/pull/12')" $(chain_cmd PreInvocation)
# shellcheck disable=SC2046
ag "ag-chain PreInvocation: quiet -> {}" ag-chain.sh '{}' "$(pre ag-coord 'status?')" $(chain_cmd PreInvocation)
# shellcheck disable=SC2046
ag "ag-chain Stop: quiet -> stop" ag-chain.sh '{"decision":"stop"}' "$(stopp ag-coord)" $(chain_cmd Stop)

echo "--- every hook has a case"
for f in "$hooks"/*.sh; do
  n="$(basename "$f")"; [[ "$n" == lib.sh ]] && continue
  [[ "$covered" == *" $n "* ]] && ok "covered: $n" || bad "no Antigravity case for hooks/$n (add one to parity-test.sh)"
done

rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
