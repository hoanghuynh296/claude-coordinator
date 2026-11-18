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
echo "---"
rm -rf "$tmp"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
