#!/usr/bin/env bash
# Pipe sample hook inputs into the coordinator hooks and check the decisions.
# Uses a temporary COORDINATOR_HOME, so the real ~/.claude/coordinator is untouched.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
hooks="$root/plugins/coordinator/hooks"
tmp="$root/tests/.work"; rm -rf "$tmp"; mkdir -p "$tmp"  # not under a temp dir: temp dirs are allowed paths
export COORDINATOR_HOME="$tmp/home"
export COORDINATOR_CC_INSTALLED="$tmp/none.json" COORDINATOR_AG_LINK="$tmp/no-link"  # the real installs never leak in
unset CLAUDE_PLUGIN_ROOT
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

echo "--- builder subagents (#64): Claude Code agent_id/agent_type, own worktree under <unit>/.claude/worktrees/builder-*"
P="$(cd "$tmp/proj" && pwd -P)"
git -C "$P" init -q && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
for w in builder-a builder-b builder-c 42-agent-session; do git -C "$P" worktree add -q "$P/.claude/worktrees/$w" -b "$w"; done
mkdir -p "$P/.claude/worktrees/builder-plain/.git" "$P/.claude/worktrees/builder-a/src"
ln -s "$P/src" "$P/.claude/worktrees/builder-b/escape"
ln -s "$P/.claude/worktrees/builder-a" "$P/.claude/worktrees/builder-link"
WT="$P/.claude/worktrees"
# units whose .claude/worktrees (P2) or .claude (P3) is a symlink out of the unit
mkdir -p "$tmp/proj2/.claude" "$tmp/proj3" "$tmp/outside/dot/worktrees"
git -C "$P" worktree add -q "$tmp/outside/wts/builder-x" -b bx
git -C "$P" worktree add -q "$tmp/outside/dot/worktrees/builder-y" -b by
ln -s "$tmp/outside/wts" "$tmp/proj2/.claude/worktrees"; ln -s "$tmp/outside/dot" "$tmp/proj3/.claude"
P2="$(cd "$tmp/proj2" && pwd -P)"; P3="$(cd "$tmp/proj3" && pwd -P)"
"$root/plugins/coordinator/scripts/register.sh" coord-1 "$tmp/ledger" "$tmp/proj" "$tmp/proj2" "$tmp/proj3" >/dev/null
CL="$COORDINATOR_HOME/state/coord-1/builders"
evs() { # session agent_id agent_type path [tool]
  printf '{"session_id":"%s","agent_id":"%s","agent_type":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$1" "$2" "$3" "$L" "${5:-Write}" "$4"
}
for mode in jq python3; do
  echo "--- builder JSON via $mode"
  if [[ $mode == python3 ]]; then export COORDINATOR_NO_JQ=1; fi
  check "coordinator itself in unit code"          deny  "$(ev coord-1 Write file_path "$P/src/app.ts")"
  check "coordinator itself in a builder worktree" deny  "$(ev coord-1 Write file_path "$WT/builder-a/src/app.ts")"
  check "builder in its worktree"                  allow "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  check "builder in its worktree, Edit, new dir"   allow "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-a/new/dir/x.md" Edit)"
  check "builder, bare agent type"                 allow "$(evs coord-1 b1 oneoff-builder "$WT/builder-b/README.md")"
  check "builder outside its worktree (unit src)"  deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$P/src/app.ts")"
  check "builder in another builder's worktree"    deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-b/README.md")"
  check "second builder in a claimed worktree"     deny  "$(evs coord-1 c1 coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  if [[ $mode == jq ]]; then  # #69: the refusal leaves no agent claim behind
    if [[ ! -e "$CL/agent-c1" ]]; then pass=$((pass+1)); echo "PASS refused builder holds no agent claim"; else failn=$((failn+1)); echo "FAIL refused builder kept agent-c1: $(cat "$CL/agent-c1")"; fi
  fi
  check "refused builder, then its own new worktree" allow "$(evs coord-1 c1 coordinator:oneoff-builder "$WT/builder-c/src/app.ts")"
  check "coordinator itself in that new worktree"  deny  "$(ev coord-1 Write file_path "$WT/builder-c/src/app.ts")"
  check "bound builder in a third worktree"        deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-c/src/app.ts")"
  check "refused builder back in the claimed one"  deny  "$(evs coord-1 c1 coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  check "builder in a session's worktree"          deny  "$(evs coord-1 d1 coordinator:oneoff-builder "$WT/42-agent-session/x.ts")"
  check "builder in a non-worktree builder-* dir"  deny  "$(evs coord-1 e1 coordinator:oneoff-builder "$WT/builder-plain/x.ts")"
  check "builder through a symlink out"            deny  "$(evs coord-1 b1 oneoff-builder "$WT/builder-b/escape/app.ts")"
  check "builder via a symlinked worktree"         deny  "$(evs coord-1 f1 oneoff-builder "$WT/builder-link/src/app.ts")"
  check "builder writing the worktree .git file"   deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-a/.git")"
  check "builder traversal out of its worktree"    deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-a/../../../src/app.ts")"
  check "other subagent type in a worktree"        deny  "$(evs coord-1 g1 general-purpose "$WT/builder-a/src/app.ts")"
  check "agent_type without agent_id (--agent)"    deny  "$(evs coord-1 '' coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  check "bad agent_id"                             deny  "$(evs coord-1 'a/../1' coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  check "builder in the ledger (coordinator rule)" allow "$(evs coord-1 a1 coordinator:oneoff-builder "$L/COORDINATION.md")"
  check "second builder via another letter case"   deny  "$(evs coord-1 c1 coordinator:oneoff-builder "$WT/builder-A/src/app.ts")"
  check "owner via another letter case"            deny  "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/BUILDER-a/src/app.ts")"
  check "owner still allowed after those"          allow "$(evs coord-1 a1 coordinator:oneoff-builder "$WT/builder-a/src/app.ts")"
  check "unit .claude/worktrees symlinked out"     deny  "$(evs coord-1 x1 coordinator:oneoff-builder "$P2/.claude/worktrees/builder-x/a.ts")"
  check "unit .claude symlinked out"               deny  "$(evs coord-1 y1 coordinator:oneoff-builder "$P3/.claude/worktrees/builder-y/a.ts")"
done
unset COORDINATOR_NO_JQ
out="$(evs coord-1 a1 coordinator:oneoff-builder "$P/src/app.ts" | bash "$hooks/coordinator-guard.sh")"
expect_has() { # needle output [label]
  if [[ "$2" == *"$1"* ]]; then pass=$((pass+1)); echo "PASS deny names: $1 ${3:-}"; else failn=$((failn+1)); printf 'FAIL deny lacks %s %s\n%s\n' "$1" "${3:-}" "$2"; fi; }
expect_has "own worktree <unit>/.claude/worktrees/builder-<name>/" "$out"
c="builder worktree claims"
expect_has "$c" "$(evs coord-1 c1 coordinator:oneoff-builder "$CL/wt-1-2" | bash "$hooks/coordinator-guard.sh")" "(builder)"
expect_has "$c" "$(ev coord-1 Write file_path "$CL/agent-c1" | bash "$hooks/coordinator-guard.sh")" "(coordinator)"
expect_has "$c" "$(ev coord-1 Edit file_path "$COORDINATOR_HOME/STATE/coord-1/Builders/agent-a1" | bash "$hooks/coordinator-guard.sh")" "(case)"
expect_has "$c" "$(ev coord-1 Write file_path "$CL" | bash "$hooks/coordinator-guard.sh")" "(dir itself)"
ln -s "$CL" "$tmp/claims-link"
expect_has "$c" "$(ev coord-1 Write file_path "$tmp/claims-link/agent-c1" | bash "$hooks/coordinator-guard.sh")" "(symlink)"
owners="$(cat "$CL"/wt-* | sort | tr '\n' ' ')"  # a refused builder holds no claim (#69)
if [[ "$owners" == "a1 b1 c1 " ]]; then pass=$((pass+1)); echo "PASS worktree claims: a1, b1 and c1 only"; else failn=$((failn+1)); echo "FAIL worktree claims: $owners"; fi
agents="$(cd "$CL" && ls agent-* | tr '\n' ' ')"
if [[ "$agents" == "agent-a1 agent-b1 agent-c1 " ]]; then pass=$((pass+1)); echo "PASS agent claims: a1, b1 and c1 only"; else failn=$((failn+1)); echo "FAIL agent claims: $agents"; fi
ag_b() { printf '{"conversationId":"coord-1","agentId":"a1","agentType":"coordinator:oneoff-builder","cwd":"%s","hookEventName":"PreToolUse","toolCall":{"id":"t1","name":"write_to_file","args":{"TargetFile":"%s","CodeContent":"x"}}}' "$L" "$1" | bash "$hooks/coordinator-guard.sh"; }
out="$(ag_b "$WT/builder-a/src/app.ts")"
if [[ "$out" == '{"decision":"deny",'* ]]; then pass=$((pass+1)); echo "PASS AG: builder worktree stays guarded (no subagent fields)"; else failn=$((failn+1)); echo "FAIL AG builder: $out"; fi
if [[ "$(ag_b "$L/COORDINATION.md")" == '{"decision":"allow"}' ]]; then pass=$((pass+1)); echo "PASS AG: ledger allow output unchanged"; else failn=$((failn+1)); echo "FAIL AG ledger allow"; fi

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
echo "--- SessionStart kit line (#54): running version, newer installed -> rotate"
kv="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$root/plugins/coordinator/.claude-plugin/plugin.json" | head -n 1)"
expect_out "kit line: registered session names the running version" "Coordinator kit $kv." "$(ss coord-2 "$tmp/plain")"
expect_out "kit line: ledger hint names it too"      "Coordinator kit $kv." "$(ss new-1 "$WS")"
expect_out "kit line: unit checkout names it too"    "Coordinator kit $kv." "$(ss agent-1 "$WS/products/app")"
expect_out "kit line: ordinary folder stays silent"  EMPTY "$(ss new-3 "$tmp/plain")"
printf '{"version":2,"plugins":{"coordinator@coordinator-marketplace":[{"version":"0.9.0"},{"version":"99.0.0"}],"other@x":[{"version":"100.0.0"}]}}' >"$tmp/inst.json"
expect_out "kit line: newer installed -> rotate"     "Coordinator kit $kv runs here; 99.0.0 is installed: rotate this session at the next safe point" \
  "$(COORDINATOR_CC_INSTALLED="$tmp/inst.json" ss coord-2 "$tmp/plain")"
expect_out "kit line: newer installed, one line"     1 "$(COORDINATOR_CC_INSTALLED="$tmp/inst.json" ss coord-2 "$tmp/plain" | grep -c 'Coordinator kit')"
printf '{"plugins":{"coordinator@m":[{"version":"0.1.0"}]}}' >"$tmp/inst-old.json"
expect_out "kit line: older installed -> no rotate"  "Coordinator kit $kv." "$(COORDINATOR_CC_INSTALLED="$tmp/inst-old.json" ss coord-2 "$tmp/plain")"
printf 'not json' >"$tmp/inst-bad.json"
expect_out "kit line: unreadable install list -> fail open" "Coordinator kit $kv." "$(COORDINATOR_CC_INSTALLED="$tmp/inst-bad.json" ss coord-2 "$tmp/plain")"
echo "--- Antigravity in place (ag-install.sh checks the new tag out in the same clone)"
C="$tmp/agclone"; rm -rf "$C"; cp -R "$root/plugins/coordinator" "$C"
agss() { printf '{"conversationId":"%s","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$1" "$tmp/plain" | COORDINATOR_AG_LINK="$C" bash "$C/hooks/session-start.sh"; }
agkn() { printf '{"conversationId":"%s","hookEventName":"PreInvocation"}' "$1" | COORDINATOR_AG_LINK="$C" bash "$C/hooks/kit-notice.sh"; }
expect_out "AG in place: first start runs and records $kv" "Coordinator kit $kv." "$(agss coord-2)"
expect_out "AG in place: same version -> kit-notice {}"   '{}' "$(agkn coord-2)"
sed -i.bak "s/\"version\": \"$kv\"/\"version\": \"99.2.0\"/" "$C/plugin.json" "$C/.claude-plugin/plugin.json"
expect_out "AG in place: manifest rewritten -> rotate line once" '{"injectSteps":[{"systemMessage":{"systemMessage":"Coordinator kit '"$kv"' runs here; 99.2.0 is installed: rotate' "$(agkn coord-2)"
expect_out "AG in place: not repeated"                    '{}' "$(agkn coord-2)"
expect_out "AG in place: a later start still says rotate" "Coordinator kit $kv runs here; 99.2.0 is installed" "$(agss coord-2)"
expect_out "AG in place: a new conversation runs 99.2.0"  "Coordinator kit 99.2.0." "$(printf '{"conversationId":"ag-fresh-1","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$WS" | COORDINATOR_AG_LINK="$C" bash "$C/hooks/session-start.sh")"
expect_out "AG: unrecorded conversation -> {}"            '{}' "$(agkn never-started)"
echo "--- Claude Code: running = CLAUDE_PLUGIN_ROOT (the cache folder the session loaded)"
N="$tmp/cache/99.3.0"; rm -rf "$N"; mkdir -p "$tmp/cache"; cp -R "$root/plugins/coordinator" "$N"
sed -i.bak "s/\"version\": \"$kv\"/\"version\": \"99.3.0\"/" "$N/.claude-plugin/plugin.json"
printf '{"plugins":{"coordinator@m":[{"version":"99.3.0"}]}}' >"$tmp/inst-new.json"
ccss() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "$1" "$tmp/plain" | COORDINATOR_CC_INSTALLED="$tmp/inst-new.json" CLAUDE_PLUGIN_ROOT="$2" bash "$2/hooks/session-start.sh"; }
cckn() { printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"x"}' "$1" | COORDINATOR_CC_INSTALLED="$tmp/inst-new.json" CLAUDE_PLUGIN_ROOT="$2" bash "$2/hooks/kit-notice.sh"; }
expect_out "CC fresh session on the new cache: no rotate" "Coordinator kit 99.3.0." "$(ccss coord-2 "$N")"
expect_out "CC fresh session on the new cache: kit-notice silent" EMPTY "$(cckn coord-2 "$N")"
expect_out "CC old session (old root): rotate at its start" "Coordinator kit $kv runs here; 99.3.0 is installed" "$(ccss coord-2 "$root/plugins/coordinator")"
expect_out "CC old session: kit-notice does not repeat it" EMPTY "$(cckn coord-2 "$root/plugins/coordinator")"
rm -f "$COORDINATOR_HOME/state/coord-2/kit-notified"
expect_out "CC old session, installed later: kit-notice once" "Coordinator kit $kv runs here; 99.3.0 is installed: rotate" "$(cckn coord-2 "$root/plugins/coordinator")"
expect_out "CC old session: then silent"                 EMPTY "$(cckn coord-2 "$root/plugins/coordinator")"
expect_out "CC unrecorded session: kit-notice silent"    EMPTY "$(cckn lane-unknown "$root/plugins/coordinator")"
[[ ! -e "$COORDINATOR_HOME/state/lane-unknown" ]] && { pass=$((pass+1)); echo "PASS kit-notice writes nothing for an unrecorded session"; } \
  || { failn=$((failn+1)); echo "FAIL kit-notice created state for an unrecorded session"; }
vgt() { # a b want(0 newer|1 not)
  local r=1; if ( . "$hooks/lib.sh"; version_gt "$1" "$2" ); then r=0; fi
  if [[ "$r" == "$3" ]]; then pass=$((pass+1)); echo "PASS version_gt '$1' '$2' -> $3"
  else failn=$((failn+1)); echo "FAIL version_gt '$1' '$2': got $r want $3"; fi
}
vgt 0.12.0 0.9.1 0; vgt 0.9.1 0.12.0 1; vgt 1.0.0 1.0.0 1; vgt 0.14.0 "" 1; vgt "" 0.14.0 1
vgt 0.10.0 0.9.0 0; vgt 0.9.0 0.10.0 1; vgt 1.0.0.1 1.0.0 0; vgt 1.0.0 1.0.0.1 1; vgt 1.0.0.0 1.0.0 1; vgt 1.0.0 1.0.0.0 1; vgt 1.0 0.99.99 0; vgt v1.0.0 0.1.0 1
echo "--- PostToolUse merge reminder (fake gh: PR state from files in \$FAKE_GH_DIR)"
export FAKE_GH_DIR="$tmp/gh"; mkdir -p "$FAKE_GH_DIR"
cat >"$tmp/fake-gh" <<'GH'
#!/usr/bin/env bash
# gh pr view <N> --json state,url [-R owner/repo]; default repo o/r; state from $FAKE_GH_DIR/<owner_repo>#<N>
repo=o/r; n=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in -R|--repo) repo="${args[$((i+1))]}"; i=$((i+1)) ;; [0-9]*) [[ -z "$n" ]] && n="${args[$i]}" ;; esac
done
echo "$*" >>"$FAKE_GH_DIR/calls"
f="$FAKE_GH_DIR/${repo/\//_}#$n"
[[ -f "$f" ]] || { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1; }
[[ "$(cat "$f")" == SLOW ]] && exec sleep 30
hd="feature/x dev"; [[ -f "$f.head" ]] && hd="$(cat "$f.head")"
printf '{"state":"%s","url":"https://github.com/%s/pull/%s","headRefName":"%s","author":{"login":"%s"}}\n' "$(cat "$f")" "$repo" "$n" "${hd% *}" "${hd#* }"
GH
chmod +x "$tmp/fake-gh"; export COORDINATOR_GH="$tmp/fake-gh"
merged() { for k in "$@"; do echo MERGED >"$FAKE_GH_DIR/${k/\//_}"; done; }
merged 'o/r#12' 'o/r#13' 'o/r2#13' 'o/r3#14' 'o/r#7' 'o/r#21' 'o/r#22'
merged 'o/r#30' 'a/b#6' 'o/r#31' 'o/r#32' 'a/b#33' 'o/r#34'
echo OPEN >"$FAKE_GH_DIR/o_r#16"; echo OPEN >"$FAKE_GH_DIR/o_r#15"
for n in 40 41 42 43 44 45; do echo SLOW >"$FAKE_GH_DIR/o_r#$n"; done
mr() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' "$1" "$tmp" "$2" | bash "$hooks/merge-reminder.sh"; }
pend() { awk '{printf "%s ", $1}' "$COORDINATOR_HOME/state/$1/pending-next" 2>/dev/null; }
expect_eq() { # name want got
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); echo "PASS $1"
  else failn=$((failn+1)); printf 'FAIL %s (want "%s", got "%s")\n' "$1" "$2" "$3"; fi
}
sm() { # session tool text
  python3 -I -c 'import json,sys; t=sys.argv[2]; i={"to":"Agent: api","message":sys.argv[3],"summary":"x"} if t=="SendMessage" else {"session_id":"local_x","message":sys.argv[3]}; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"PostToolUse","tool_name":t,"tool_input":i,"tool_response":{}}))' "$1" "$2" "$3" \
    | bash "$hooks/next-sent.sh"; }
stop() { # session stop_hook_active
  printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2" | bash "$hooks/next-guard.sh"; }
reset() { rm -rf "$COORDINATOR_HOME/state"; }

for mode in jq python3; do
  echo "--- merge / Next / Stop via $mode"
  if [[ $mode == python3 ]]; then export COORDINATOR_NO_JQ=1; fi
  reset
  expect_out "merge by coordinator: archive reminder"  "archive_session" "$(mr coord-1 'gh pr merge 12 --repo o/r --merge --delete-branch')"
  expect_eq  "merge records o/r#12"                    "o/r#12 " "$(pend coord-1)"
  expect_out "merge after &&: reminder"                "archive_session" "$(mr coord-1 'true && gh pr merge 13')"
  expect_eq  "no --repo: repo from gh's url"           "o/r#12 o/r#13 " "$(pend coord-1)"
  expect_out "merge reminder: archive alone (#52)"     "archive_session, alone in its own message" "$(mr coord-1 'gh pr merge 14 --repo o/r2 --merge')"
  expect_out "gh pr view: silent"                      EMPTY "$(mr coord-1 'gh pr view 12')"
  expect_out "merge by unregistered session: silent"   EMPTY "$(mr lane-7 'gh pr merge 12')"
  expect_eq  "unregistered: no state"                  "" "$(ls "$COORDINATOR_HOME/state" | grep lane-7 || true)"
  mr coord-1 'gh pr merge -R o/r2 --squash \"#13\" && gh pr merge https://github.com/o/r3/pull/14 --merge' >/dev/null
  expect_eq  "-R, quoted #N, URL; same N in two repos"  "o/r#12 o/r#13 o/r2#13 o/r3#14 " "$(pend coord-1)"
  mr coord-1 'gh pr merge --subject \"fix: a b\" --body \"x y\" 7 --squash' >/dev/null
  expect_eq  "quoted subject: PR is 7, not a word of it" "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"
  out="$(mr coord-1 'echo gh pr merge 21; echo \"gh pr merge 22\"')"
  expect_eq  "echo gh pr merge: not a merge"           "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"
  expect_eq  "echo gh pr merge: silent (nothing ran)"  "" "$out"
  expect_out "heredoc body with gh pr merge: silent"   EMPTY "$(mr coord-1 'cat <<EOF > n.md\ngh pr merge 12 --merge\nEOF\ngit add n.md')"
  expect_out "quoted heredoc + <<- tabs: silent"       EMPTY "$(mr coord-1 'cat <<-\"EOF\"\n\tgh pr merge 12\n\tEOF')"
  expect_out "double-quoted string: silent"            EMPTY "$(mr coord-1 'git commit -m \"docs: gh pr merge 12\"')"
  expect_out "comment line: silent"                    EMPTY "$(mr coord-1 'ls # then gh pr merge 12\n# gh pr merge 13')"
  expect_out "heredoc then a real merge: recorded"     "merged o/r#31" "$(mr coord-1 'cat <<EOF\ngh pr merge 12\nEOF\ngh pr merge 31')"
  expect_out "bash -c merge: recorded"                 "merged o/r#32" "$(mr coord-1 'bash -c \"gh pr merge 32 --squash\"')"
  merged 'o/r#70' 'a/b#71' 'o/r#72' 'o/r#73' 'o/r#74' 'o/r#75' 'o/r#76'
  expect_out "bash -lc: recorded"                      "merged o/r#70" "$(mr coord-1 'bash -lc \"gh pr merge 70\"')"
  expect_out "gh -R x pr merge: recorded"              "merged a/b#71" "$(mr coord-1 'gh -R a/b pr merge 71 --squash')"
  expect_out "sudo -u me gh pr merge: recorded"        "merged o/r#72" "$(mr coord-1 'sudo -u me gh pr merge 72')"
  expect_out "echo \"\$(gh pr merge N)\": recorded"     "merged o/r#73" "$(mr coord-1 'echo \"$(gh pr merge 73)\"')"
  expect_out "backticks: recorded"                     "merged o/r#74" "$(mr coord-1 'echo `gh pr merge 74`')"
  expect_out "\$((1<<2)) is not a heredoc: recorded"   "merged o/r#75" "$(mr coord-1 'echo $((1<<2)); gh pr merge 75')"
  expect_out "unreadable merge inside \$(): reminder"  "could not be read" "$(mr coord-1 'x=$(gh pr merge $P)')"
  expect_out "quoted <<'EOF' heredoc: silent"          EMPTY "$(mr coord-1 'cat <<\x27EOF\x27\ngh pr merge 12\nEOF')"
  expect_out "non-zero exit but MERGED: recorded"      "merged o/r#76" "$(printf '{"session_id":"coord-1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr merge 76 && git pull"},"tool_response":{"exit_code":1}}' "$tmp" | bash "$hooks/merge-reminder.sh")"
  expect_out "non-zero exit, PR still OPEN: silent"    EMPTY "$(printf '{"session_id":"coord-1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr merge 16"},"tool_response":{"exit_code":1}}' "$tmp" | bash "$hooks/merge-reminder.sh")"
  fx() { printf '{"session_id":"coord-1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"exit_code":1}}' "$tmp" "$1" | bash "$hooks/merge-reminder.sh"; }
  expect_out "exit 1, gh cannot confirm: reminder"     "could not confirm" "$(fx 'gh pr merge 99 && git pull')"
  expect_out "exit 1, unreadable PR: reminder"         "could not be read" "$(fx 'bash -lc \"gh pr merge $P\"')"
  merged 'o/r#78' 'a/b#79' 'o/r#80'
  expect_out "GH_REPO= prefix: -R from it"             "merged a/b#79" "$(mr coord-1 'GH_REPO=a/b gh pr merge 79')"
  expect_out "cd first: not looked up, reminder"       "changed directory" "$(mr coord-1 'cd other && gh pr merge 78')"
  expect_out "cd first but -R given: recorded"         "merged o/r#80" "$(mr coord-1 'cd other && gh pr merge 80 -R o/r')"
  for k in o/r#70 a/b#71 o/r#72 o/r#73 o/r#74 o/r#75 o/r#76 a/b#79 o/r#80; do bash "$root/plugins/coordinator/scripts/next-clear.sh" coord-1 "$k" "test" >/dev/null 2>&1; done
  for k in o/r#31 o/r#32; do bash "$root/plugins/coordinator/scripts/next-clear.sh" coord-1 "$k" "test" >/dev/null 2>&1; done
  expect_eq  "false positives recorded nothing"        "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"
  expect_out "failed merge then '; echo ok': silent"   EMPTY "$(mr coord-1 'gh pr merge 16; echo ok')"
  mr coord-1 'gh pr merge 16 || true' >/dev/null
  expect_eq  "failed merge (still OPEN) not recorded"  "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"
  expect_out "--auto still queued: not recorded, says so" "queued the merge" "$(mr coord-1 'gh pr merge 15 --auto --squash')"
  expect_out "--auto on a ready PR: merged, recorded"  "merged o/r#30" "$(mr coord-1 'gh pr merge 30 --auto --squash')"
  mr coord-1 'if true; then gh pr merge 6 -R a/b; fi' >/dev/null
  mr coord-1 'env GH_PROMPT_DISABLED=1 gh pr merge 31 && nohup gh pr merge 32 >/dev/null' >/dev/null
  mr coord-1 'while false; do :; done; { gh pr merge 33 -R a/b; }; ! gh pr merge 34' >/dev/null
  expect_eq  "merges inside if/env/nohup/{}/! recorded" "o/r#30 a/b#6 o/r#31 o/r#32 a/b#33 o/r#34 " "$(pend coord-1 | sed 's/^.*o\/r#7 //')"
  expect_out "for loop with \$p: fail-open reminder"   "could not be read" "$(mr coord-1 'for p in 1 2; do gh pr merge $p; done')"
  expect_out "xargs gh pr merge: fail-open reminder"   "could not be read" "$(mr coord-1 'echo 5 | xargs -n1 gh pr merge')"
  for k in o/r#30 a/b#6 o/r#31 o/r#32 a/b#33 o/r#34; do bash "$root/plugins/coordinator/scripts/next-clear.sh" coord-1 "$k" "test" >/dev/null 2>&1; done
  expect_out "gh cannot answer: reminder, not recorded" "could not confirm" "$(mr coord-1 'gh pr merge 99')"
  expect_out "branch-name merge: asks for the number"  "could not be read" "$(mr coord-1 'gh pr merge feature-x')"
  expect_eq  "still five pending"                      "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"

  out="$(stop coord-1 false)"
  expect_out "Stop blocks while pending"               '"decision":"block"' "$out"
  expect_out "Stop reason names each PR"               'o/r2#13' "$out"
  expect_out "Stop reason gives the format"            'PR #14 merged. Next:' "$out"
  expect_out "Stop reason gives the escape hatch"      'next-clear.sh' "$out"

  expect_eq  "message without Next: keeps pending"     "" "$(sm coord-1 SendMessage 'PR #12 merged.')"
  expect_eq  "wrong PR number keeps pending"           "" "$(sm coord-1 SendMessage $'PR #98 merged.\nNext: #50')"
  expect_eq  "empty Next: keeps pending"               "" "$(sm coord-1 SendMessage 'PR #12 merged. Next:   ')"
  expect_eq  "unregistered sender: silent"             "" "$(sm lane-7 SendMessage 'PR #12 merged. Next: #50')"
  expect_out "bare #13 in two repos: not cleared"      "more than one repo" "$(sm coord-1 SendMessage 'PR #13 merged. Next: #50')"
  expect_eq  "still five after the ambiguous notice"   "o/r#12 o/r#13 o/r2#13 o/r3#14 o/r#7 " "$(pend coord-1)"
  expect_out "PR o/r2#13 clears only that one"         "Next sent for o/r2#13" "$(sm coord-1 SendMessage 'PR o/r2#13 merged. Next: stand by')"
  expect_out "now bare #13 clears o/r#13"              "Next sent for o/r#13" "$(sm coord-1 SendMessage 'PR #13 merged. Next: handover')"
  expect_out "notice clears #12, lists what is left"   "Still pending: o/r3#14 o/r#7" "$(sm coord-1 SendMessage 'PR #12 merged. Next: #50 https://github.com/o/r/issues/50')"
  expect_out "send_message {session_id,message}, Next on its own line" "Next sent for o/r3#14" \
    "$(sm coord-1 mcp__ccd_session_mgmt__send_message $'PR #14 merged.\nNext: done')"
  expect_eq  "only o/r#7 left"                         "o/r#7 " "$(pend coord-1)"

  rm -f "$COORDINATOR_HOME/state/coord-1/stop-blocks"
  expect_out "turn end: block 1"                       '"decision":"block"' "$(stop coord-1 false)"
  expect_out "continued: block 2"                      '"decision":"block"' "$(stop coord-1 true)"
  expect_out "continued: block 3"                      '"decision":"block"' "$(stop coord-1 true)"
  out="$(stop coord-1 true)"
  expect_out "continued: 4th stop allowed, warning"    'systemMessage' "$out"
  [[ "$out" != *'"decision":"block"'* ]] && { pass=$((pass+1)); echo "PASS 4th stop is not blocked"; } || { failn=$((failn+1)); echo "FAIL 4th stop blocked"; }
  expect_out "next turn blocks again"                  '"decision":"block"' "$(stop coord-1 false)"
  merged 'o/r8#60'; mr coord-1 'gh pr merge 60 -R o/r8' >/dev/null
  expect_out "Stop reason names the same-session form" '(same session)' "$(stop coord-1 false)"
  expect_out "same-session Next clears the guard"      "Next sent for o/r8#60" "$(sm coord-1 SendMessage 'PR o/r8#60 merged. Next: #51 (same session)')"
  expect_eq  "only o/r#7 left after same-session Next" "o/r#7 " "$(pend coord-1)"
  expect_eq  "unregistered Stop: silent"               "" "$(stop lane-7 false)"
  expect_eq  "registered, nothing pending: silent"     "" "$(stop coord-2 false)"
done
unset COORDINATOR_NO_JQ

echo "--- exempt PRs (release/*, backmerge/*, coordinator/*, \$COORDINATOR_GH_LOGIN) are never pending"
rm -rf "$COORDINATOR_HOME/state/coord-3"
merged 'o/r#90' 'o/r#91' 'o/r#92' 'o/r#93' 'o/r#94' 'o/r#97'
echo "release/v1.2.0 dev" >"$FAKE_GH_DIR/o_r#90.head"
echo "backmerge/v1.2.0 dev" >"$FAKE_GH_DIR/o_r#91.head"
echo "feature/y claude-coord" >"$FAKE_GH_DIR/o_r#92.head"
echo "releases/x dev" >"$FAKE_GH_DIR/o_r#93.head"
echo "coordinator/agent-made dev" >"$FAKE_GH_DIR/o_r#94.head"
echo "feature/z dev" >"$FAKE_GH_DIR/o_r#97.head"
expect_out "release/* PR merged: silent, not recorded"  EMPTY "$(mr coord-3 'gh pr merge 90')"
expect_out "backmerge/* PR merged: silent"              EMPTY "$(mr coord-3 'gh pr merge 91')"
expect_out "coordinator/* PR (even agent-named): exempt" EMPTY "$(mr coord-3 'gh pr merge 94')"
expect_eq  "exempt PRs recorded nothing"                "" "$(pend coord-3)"
mr coord-3 'gh pr merge 92; gh pr merge 93; gh pr merge 97' >/dev/null
expect_eq  "feature/ and releases/ heads are pending"   "o/r#92 o/r#93 o/r#97 " "$(pend coord-3)"
rm -rf "$COORDINATOR_HOME/state/coord-3"
COORDINATOR_GH_LOGIN=claude-coord mr coord-3 'gh pr merge 92; gh pr merge 97' >/dev/null
expect_eq  "author == COORDINATOR_GH_LOGIN exempt, others not" "o/r#97 " "$(pend coord-3)"
n0="$(wc -l <"$FAKE_GH_DIR/calls")"
out="$(stop coord-3 false)"
expect_out "Stop blocks for the pending agent PR"       '"decision":"block"' "$out"
expect_eq  "next-guard makes no gh call"                "$n0" "$(wc -l <"$FAKE_GH_DIR/calls")"
rm -rf "$COORDINATOR_HOME/state/coord-3"
echo SLOW >"$FAKE_GH_DIR/o_r#98"; echo "release/v9 dev" >"$FAKE_GH_DIR/o_r#98.head"
out="$(COORDINATOR_GH_DEADLINE=1 mr coord-3 'gh pr merge 98')"
expect_out "hung gh: not exempted, reminder shown"      "could not confirm" "$out"
rm -f "$FAKE_GH_DIR/o_r#98" "$FAKE_GH_DIR/o_r#98.head"

echo "--- one total deadline for every gh lookup"
t0=$SECONDS
out="$(COORDINATOR_GH_DEADLINE=2 mr coord-3 'gh pr merge 40; gh pr merge 41; gh pr merge 42; gh pr merge 43; gh pr merge 44; gh pr merge 45')"
el=$((SECONDS - t0))
(( el <= 5 )) && { pass=$((pass+1)); echo "PASS six hung gh calls end within the 2 s deadline (${el}s)"; } \
  || { failn=$((failn+1)); echo "FAIL six hung gh calls took ${el}s with a 2 s deadline"; }
expect_out "hung gh: reminder, nothing recorded"       "could not confirm" "$out"
expect_eq  "hung gh: no pending"                        "" "$(pend coord-3)"
python3 -I -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]; t=[x.get("timeout",0) for e in h["PostToolUse"] for x in e["hooks"] if "merge-reminder" in x["command"]]; sys.exit(0 if t and t[0] >= 30 else 1)' "$hooks/hooks.json" \
  && { pass=$((pass+1)); echo "PASS hooks.json gives merge-reminder a timeout above the deadline"; } || { failn=$((failn+1)); echo "FAIL merge-reminder timeout in hooks.json"; }

echo "--- escape hatch and handover: next-clear.sh"
nc="$root/plugins/coordinator/scripts/next-clear.sh"
merged 'o/r9#7'; mr coord-1 'gh pr merge 7 -R o/r9' >/dev/null
if bash "$nc" coord-1 'o/r#7' >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL clear without reason accepted"; else pass=$((pass+1)); echo "PASS clear without reason rejected"; fi
if bash "$nc" lane-7 'o/r#7' "x" >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL unregistered clear accepted"; else pass=$((pass+1)); echo "PASS unregistered clear rejected"; fi
if bash "$nc" coord-1 7 "x" >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL ambiguous bare 7 cleared"; else pass=$((pass+1)); echo "PASS ambiguous bare 7 rejected"; fi
mkdir -p "$L/coordination"
bash "$nc" coord-1 'o/r#7' "author session archived before the merge" >/dev/null
expect_eq  "cleared: o/r9#7 left"                      "o/r9#7 " "$(pend coord-1)"
expect_out "reason is in the ledger"                   "o/r#7: author session archived" "$(cat "$L/coordination/next-cleared.md")"
expect_eq  "--handover prints the list"                "o/r9#7" "$(bash "$nc" coord-1 --handover)"
expect_eq  "--handover drops the old state"            "no" "$([[ -d "$COORDINATOR_HOME/state/coord-1" ]] && echo yes || echo no)"
expect_eq  "old session's Stop then allowed"           "" "$(stop coord-1 false)"
bash "$nc" coord-2 --add 'o/r9#7' >/dev/null
expect_eq  "replacement takes it over (--add)"         "o/r9#7 " "$(pend coord-2)"
expect_out "replacement's Stop blocks"                 '"decision":"block"' "$(stop coord-2 false)"
if bash "$nc" coord-2 --add 'bad' >/dev/null 2>&1; then failn=$((failn+1)); echo "FAIL --add accepted a bad key"; else pass=$((pass+1)); echo "PASS --add rejects a bad key"; fi
"$root/plugins/coordinator/scripts/register.sh" --unregister coord-2 >/dev/null
expect_eq  "unregister removes hook state"             "no" "$([[ -d "$COORDINATOR_HOME/state/coord-2" ]] && echo yes || echo no)"
nopy="$tmp/nopy"; mkdir -p "$nopy"
for c in bash cat sed head awk grep mkdir mv rm date dirname jq tr; do p="$(command -v $c 2>/dev/null)" && ln -sf "$p" "$nopy/$c"; done
echo "--- CI watch reminder fails open without python3"
"$root/plugins/coordinator/scripts/register.sh" coord-7 "$tmp/ledger" "$tmp/proj" >/dev/null
expect_out "no python3: phrase anywhere -> reminder"   'run_in_background' "$(printf '{"session_id":"coord-7","hook_event_name":"UserPromptSubmit","prompt":"x PR ready #3"}' | PATH="$nopy" "$nopy/bash" "$hooks/ci-watch-reminder.sh")"
expect_out "no python3: other prompt -> silent"        EMPTY "$(printf '{"session_id":"coord-7","hook_event_name":"UserPromptSubmit","prompt":"status?"}' | PATH="$nopy" "$nopy/bash" "$hooks/ci-watch-reminder.sh")"
echo "--- CI watch reminder on \"PR ready\" (UserPromptSubmit, inbox tools)"
"$root/plugins/coordinator/scripts/register.sh" coord-6 "$tmp/ledger" "$tmp/proj" >/dev/null
up() { python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"UserPromptSubmit","prompt":sys.argv[2]}))' "$1" "$2" | bash "$hooks/ci-watch-reminder.sh"; }
rn() { python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"PostToolUse","tool_name":"ReadNotifications","tool_input":{},"tool_response":{"notifications":[{"body":sys.argv[2]}]}}))' "$1" "$2" | bash "$hooks/ci-watch-reminder.sh"; }
for mode in jq python3; do
  if [[ $mode == python3 ]]; then export COORDINATOR_NO_JQ=1; fi
  r="$(up coord-6 'PR ready: #12 https://github.com/o/r/pull/12 head abc1234, CI pending. Context: 80k')"
  expect_out "$mode: PR ready prompt -> start the watch"   'run_in_background' "$r"
  expect_out "$mode: names the event"                       '"hookEventName":"UserPromptSubmit"' "$r"
  expect_out "$mode: ready-to-run command for the PR link"  ' o/r 12 <head sha>' "$r"
  expect_out "$mode: case-insensitive"                      'ci-watch.sh' "$(up coord-6 'pr ready: #3')"
  expect_out "$mode: inbox tool result -> reminder"         '"hookEventName":"PostToolUse"' "$(rn coord-6 'PR ready https://github.com/a/b/pull/4')"
  expect_out "$mode: quoted on a later line -> silent"      EMPTY "$(up coord-6 $'Progress on #12.\nAgent said: PR ready https://github.com/o/r/pull/12')"
  expect_out "$mode: progress note mentioning it -> silent" EMPTY "$(up coord-6 'Still working; will send PR ready once the gate is green')"
  expect_out "$mode: quote at the start of a line 2 -> silent" EMPTY "$(up coord-6 $'> forwarded:\n> PR ready #3')"
  expect_out "$mode: first line starts with PR ready"       'run_in_background' "$(up coord-6 $'PR ready: o/r#12 abc\nmore')"
  expect_out "$mode: inbox, wrapped message"                'run_in_background' "$(rn coord-6 $'<cross-session-message from=\"Agent: x\">\nPR ready: o/r#4 abc')"
  expect_out "$mode: inbox, phrase only in a later line"    EMPTY "$(rn coord-6 $'Status\nPR ready #4')"
  expect_out "$mode: inline wrapper"                        'run_in_background' "$(rn coord-6 '<cross-session-message from="x">PR ready: #3')"
  expect_out "$mode: blank line before the first line"      'run_in_background' "$(up coord-6 $'\n\nPR ready: #3')"
  expect_out "$mode: other prompt -> silent"                EMPTY "$(up coord-6 'what is the status?')"
  expect_out "$mode: unregistered session -> silent"        EMPTY "$(up lane-7 'PR ready #3')"
done
unset COORDINATOR_NO_JQ
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$hooks/hooks.json" && { pass=$((pass+1)); echo "PASS hooks.json parses"; } \
  || { failn=$((failn+1)); echo "FAIL hooks.json does not parse"; }

echo "--- Antigravity hook payloads (conversationId, toolCall.args, continuationActive)"
ag_ev() { # convId tool Path
  printf '{"conversationId":"%s","cwd":"%s","artifactDirectoryPath":"/private/tmp/ag-brain/a","hookEventName":"PreToolUse","toolCall":{"id":"t1","name":"%s","args":{"Path":"%s","Content":"x"}}}' "$1" "$P" "$2" "$3"
}
expect_out "AG guard: ledger file allowed"           '{"decision":"allow"}' "$(ag_ev coord-1 write_file "$L/COORDINATION.md" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG guard: docs/PLAN.md allowed"          '{"decision":"allow"}' "$(ag_ev coord-1 edit_file "$P/docs/PLAN.md" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG guard: artifactDirectoryPath allowed" '{"decision":"allow"}' "$(ag_ev coord-1 write_file "/private/tmp/ag-brain/a/plan.md" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG guard: ~/.gemini allowed"             '{"decision":"allow"}' "$(ag_ev coord-1 write_file "$HOME/.gemini/antigravity/x.md" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG guard: unit code denied"              '"decision":"deny"'    "$(ag_ev coord-1 edit_file "$P/src/app.ts" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG guard: unregistered allowed"          '{"decision":"allow"}' "$(ag_ev lane-7 edit_file "$P/src/app.ts" | bash "$hooks/coordinator-guard.sh")"
expect_out "AG SessionStart: registered JSON"        '"injectSteps"'        "$(printf '{"conversationId":"coord-1","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$P" | bash "$hooks/session-start.sh")"
expect_out "AG SessionStart: unregistered ledger"    'session id ag-new-1'  "$(printf '{"conversationId":"ag-new-1","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$WS" | bash "$hooks/session-start.sh")"
expect_out "AG SessionStart: plain folder -> {}"     '{}'                   "$(printf '{"conversationId":"ag-new-2","workspacePaths":["%s"],"hookEventName":"SessionStart"}' "$tmp/plain" | bash "$hooks/session-start.sh")"

reset
merged 'o/r#12'
ag_mr="$(printf '{"conversationId":"coord-1","cwd":"%s","hookEventName":"PostToolUse","toolCall":{"id":"t2","name":"run_command","args":{"CommandLine":"gh pr merge 12 --repo o/r --merge"}}}' "$tmp" | bash "$hooks/merge-reminder.sh")"
expect_eq  "AG PostToolUse returns {}"               "{}" "$ag_mr"
expect_eq  "AG merge records o/r#12"                 "o/r#12 " "$(pend coord-1)"
ag_stop="$(printf '{"conversationId":"coord-1","hookEventName":"Stop","continuationActive":false}' | bash "$hooks/next-guard.sh")"
expect_out "AG Stop returns decision:continue"       '"decision":"continue"' "$ag_stop"
expect_out "AG Stop names o/r#12"                    'o/r#12' "$ag_stop"
ag_sm="$(printf '{"conversationId":"coord-1","hookEventName":"PostToolUse","toolCall":{"id":"t3","name":"send_message","args":{"Recipient":"w1","Message":"PR #12 merged. Next: #50"}}}' | bash "$hooks/next-sent.sh")"
expect_eq  "AG next-sent returns {}"                 "{}" "$ag_sm"
expect_eq  "AG next-sent clears o/r#12"              "" "$(pend coord-1)"
expect_eq  "AG Stop when nothing pending -> stop"    '{"decision":"stop"}' "$(printf '{"conversationId":"coord-1","hookEventName":"Stop","continuationActive":false}' | bash "$hooks/next-guard.sh")"
ag_ci="$(printf '{"conversationId":"coord-6","hookEventName":"PreInvocation","lastUserInput":"PR ready: https://github.com/o/r/pull/12 head abc1234"}' | bash "$hooks/ci-watch-reminder.sh")"
expect_out "AG PreInvocation PR ready -> injectSteps" '"injectSteps"' "$ag_ci"
expect_out "AG PreInvocation includes ci-watch cmd"   'o/r 12 <head sha>' "$ag_ci"
expect_eq  "AG PreInvocation ordinary input -> {}"    "{}" "$(printf '{"conversationId":"coord-6","hookEventName":"PreInvocation","lastUserInput":"status?"}' | bash "$hooks/ci-watch-reminder.sh")"

echo "---"
rm -rf "$tmp"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
