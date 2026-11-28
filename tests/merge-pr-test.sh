#!/usr/bin/env bash
# scripts/merge-pr.sh against a fake gh: refuses on closed, stale head, red, pending and no
# checks (no merge); merges with the right flags; closes linked issues off the default branch;
# records the pending Next so the Stop guard holds (Claude Code and Antigravity payloads);
# exempt heads; per-issue archive line and worktree removal; at most 6 lines; refuses a base the
# profile's "Owner approves merges into:" names unless --owner-approved.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
plugin="$root/plugins/coordinator"
script="$plugin/scripts/merge-pr.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2"; return 0; }
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# Fake gh. $FAKE/view: pr view JSON; $FAKE/checks: pr checks output ("ERR <text>" fails);
# pr merge appends its args to $FAKE/merge.log and marks the PR merged ($FAKE/merge-fail: fails);
# issue close appends to $FAKE/close.log; repo view prints $FAKE/default.
cat >"$tmp/gh" <<'GH'
#!/usr/bin/env bash
F="$FAKE"
out() { local c; c="$(cat "$1")"; if [[ "$c" == ERR* ]]; then echo "${c#ERR }" >&2; exit 1; fi; printf '%s\n' "$c"; }
case "$1 $2" in
  "pr view") if [[ " $* " == *" --jq .state "* ]]; then [[ -f "$F/state-fail" ]] && { echo "timeout" >&2; exit 1; }
               [[ -f "$F/merged" ]] && echo MERGED || echo OPEN
             else out "$F/view"; fi ;;
  "pr checks") out "$F/checks" ;;
  "pr merge") echo "$*" >>"$F/merge.log"
              [[ -f "$F/merge-landed-fail" ]] && { touch "$F/merged"; echo "failed to delete branch" >&2; exit 1; }
              [[ -f "$F/merge-fail" ]] && { echo "GraphQL: Head branch was modified" >&2; exit 1; }
              touch "$F/merged" ;;
  "issue close") echo "$*" >>"$F/close.log" ;;
  "repo view") cat "$F/default" ;;
  "pr list") echo "[]" ;;
esac
GH
chmod +x "$tmp/gh"
export COORDINATOR_GH="$tmp/gh" COORDINATOR_HOME="$tmp/home"
unset COORDINATOR_SESSION_ID COORDINATOR_GH_LOGIN
SID=coord-sess-1
mkdir -p "$COORDINATOR_HOME/sessions"; printf 'ledger=%s\nproject=%s\n' "$tmp/ledger" "$tmp" >"$COORDINATOR_HOME/sessions/$SID"
SHA=abcdef1234567890abcdef1234567890abcdef12

# case_ [head ref] [base] [state] [author]
case_() {
  rm -rf "$tmp/f"; mkdir -p "$tmp/f"; export FAKE="$tmp/f"
  rm -rf "$COORDINATOR_HOME/state"
  printf '{"state":"%s","url":"https://github.com/%s/pull/7","headRefOid":"%s","headRefName":"%s","baseRefName":"%s","author":{"login":"%s"},"closingIssuesReferences":[{"number":12,"repository":{"name":"r","owner":{"login":"o"}}}]}' \
    "${3:-OPEN}" "${5:-o/r}" "$SHA" "${1:-feat/12-x}" "${2:-develop}" "${4:-agent-bot}" >"$FAKE/view"
  echo '[{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"skipping"}]' >"$FAKE/checks"
  echo main >"$FAKE/default"
}
# run <args...>: sets out, rc
run() { rc=0; out="$(bash "$script" "$@" 2>&1)" || rc=$?; }
expect() { # name rc needle
  if [[ $rc -eq $2 && "$out" == *"$3"* ]]; then ok "$1"; else bad "$1 (rc $rc, want $2, needle '$3')" "$out"; fi; }
nomerge() { [[ ! -f "$FAKE/merge.log" ]] && ok "$1: no merge" || bad "$1: merged anyway"; }
lines() { printf '%s\n' "$out" | wc -l | tr -d ' '; }

# Refusals
case_ x x MERGED; run o/r 7 abcdef1 --session $SID
expect "merged PR is refused" 1 "refused: o/r#7 is merged, not open"; nomerge "merged"
case_ x x CLOSED; run o/r 7 abcdef1 --session $SID
expect "closed PR is refused" 1 "is closed, not open"; nomerge "closed"
case_; run o/r 7 1234567 --session $SID
expect "stale head is refused" 1 "refused: stale head: o/r#7 head is abcdef1, reviewed 1234567"; nomerge "stale"
case_; echo '[{"name":"tests","bucket":"fail"},{"name":"lint","bucket":"pass"}]' >"$FAKE/checks"; run o/r 7 abcdef1 --session $SID
expect "red CI is refused" 1 "refused: CI red on abcdef1: tests"; nomerge "red"
case_; echo '[{"name":"tests","bucket":"pending"}]' >"$FAKE/checks"; run o/r 7 abcdef1 --session $SID
expect "pending CI is refused" 1 "refused: CI pending on abcdef1: tests"; nomerge "pending"
case_; echo "ERR no checks reported on the 'feat' branch" >"$FAKE/checks"; run o/r 7 abcdef1 --session $SID
expect "no checks is refused" 1 "refused: no CI checks"; nomerge "no checks"
[[ "$(lines)" == 1 ]] && ok "a refusal is one line" || bad "a refusal is one line" "$out"
case_; echo "ERR HTTP 404" >"$FAKE/view"; run o/r 7 abcdef1 --session $SID
expect "gh error exits 2" 2 "error: gh pr view: HTTP 404"; nomerge "gh error"
run o/r seven abcdef1; expect "bad args are usage" 2 "Usage"

# Merge into develop: flags, issue closed, pending recorded, Next line
case_; run o/r 7 abcdef1 --session $SID
expect "merges and reports" 0 "merge-pr: o/r#7 merged into develop (merge, abcdef1); closed o/r#12"
grep -q -- "pr merge 7 -R o/r --merge --delete-branch --match-head-commit $SHA" "$FAKE/merge.log" \
  && ok "merge uses --merge --delete-branch --match-head-commit <full sha>" || bad "merge flags" "$(cat "$FAKE/merge.log")"
grep -q -- 'issue close 12 -R o/r --comment Merged in o/r#7' "$FAKE/close.log" && ok "linked issue closed with comment" \
  || bad "linked issue closed" "$(cat "$FAKE/close.log" 2>/dev/null)"
[[ "$out" == *"send to the author: PR #7 merged. Next: done"* ]] && ok "prints the Next line" || bad "prints the Next line" "$out"
[[ "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" == "o/r#7" ]] && ok "pending Next recorded in the session state" \
  || bad "pending Next recorded"
[[ "$(lines)" -le 6 ]] && ok "at most 6 lines" || bad "at most 6 lines" "$out"

# The Stop guard holds the turn on both runtimes, and the sent message clears it
o="$(printf '{"session_id":"%s","stop_hook_active":false}' $SID | bash "$plugin/hooks/next-guard.sh")"
[[ "$o" == *'"decision":"block"'*"o/r#7"* ]] && ok "Stop guard blocks (Claude Code)" || bad "Stop guard blocks (Claude Code)" "$o"
rm -f "$COORDINATOR_HOME/state/$SID/stop-blocks"
o="$(printf '{"conversationId":"%s"}' $SID | bash "$plugin/hooks/next-guard.sh")"
[[ "$o" == *'"decision":"continue"'*"o/r#7"* ]] && ok "Stop guard holds (Antigravity)" || bad "Stop guard holds (Antigravity)" "$o"
printf '{"session_id":"%s","tool_name":"SendMessage","tool_input":{"to":"a","message":"PR #7 merged. Next: done"}}' $SID \
  | bash "$plugin/hooks/next-sent.sh" >/dev/null
[[ -z "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" ]] && ok "sending the printed line clears it" || bad "sending clears it"

# Default branch base: no issue close; squash from the profile; --method wins
case_ feat/12-x main; mkdir -p "$tmp/ledger/coordination"; echo "- Integration branch: main. Merge method: squash." >"$tmp/ledger/coordination/PROFILE.md"
run o/r 7 abcdef1 --session $SID --ledger "$tmp/ledger"
expect "squash from the profile" 0 "merged into main (squash, abcdef1)"
[[ ! -f "$FAKE/close.log" && "$out" != *closed* ]] && ok "no issue close on the default branch" || bad "no issue close on the default branch" "$out"
case_; run o/r 7 abcdef1 --session $SID --ledger "$tmp/ledger" --method rebase
expect "--method wins over the profile" 0 "(rebase, abcdef1)"

# Merge failure
case_; touch "$FAKE/merge-fail"; run o/r 7 abcdef1 --session $SID
expect "failed merge exits 3" 3 "merge failed: o/r#7 is OPEN: GraphQL: Head branch was modified"
[[ -z "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" ]] && ok "failed merge records nothing" || bad "failed merge records nothing"

# Exempt heads and login
for h in release/v1.2.0 backmerge/main coordinator/ledger; do
  case_ "$h"; run o/r 7 abcdef1 --session $SID
  if [[ $rc -eq 0 && "$out" == *"no Next message: exempt head $h"* && -z "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" ]]; then
    ok "exempt head $h: no pending Next"; else bad "exempt head $h" "$out"; fi
done
case_ feat/x develop OPEN owner-me; COORDINATOR_GH_LOGIN=owner-me run o/r 7 abcdef1 --session $SID
expect "PR by COORDINATOR_GH_LOGIN is exempt" 0 "no Next message"

# Session: missing or unregistered → warning, merge still reported
case_; run o/r 7 abcdef1
expect "no session warns" 0 "WARNING: no --session"
case_; COORDINATOR_SESSION_ID=$SID run o/r 7 abcdef1
expect "session from COORDINATOR_SESSION_ID" 0 "pending Next recorded for $SID"
case_; run o/r 7 abcdef1 --session nobody
expect "unregistered session warns" 0 "WARNING: nobody is not a registered coordinator"

# Same number pending in another repo → the line names the repo
case_; bash "$plugin/scripts/next-clear.sh" $SID --add other/repo#7 >/dev/null; run o/r 7 abcdef1 --session $SID
expect "same number in two repos names the repo" 0 "PR o/r#7 merged. Next: done"

# Per-issue author: archive line, worktree removed; same session: neither
mkdir -p "$tmp/g"; git init -q --bare "$tmp/g/origin.git"
git clone -q "$tmp/g/origin.git" "$tmp/g/repo" 2>/dev/null
git -C "$tmp/g/repo" commit -q --allow-empty -m init && git -C "$tmp/g/repo" push -q origin HEAD:main 2>/dev/null
git -C "$tmp/g/repo" worktree add -q -b feat/12-x "$tmp/g/repo/.claude/worktrees/agent-12" 2>/dev/null
git -C "$tmp/g/repo/.claude/worktrees/agent-12" commit -q --allow-empty -m work
git -C "$tmp/g/repo/.claude/worktrees/agent-12" push -q origin feat/12-x 2>/dev/null
case_; run o/r 7 abcdef1 --session $SID --per-issue "Agent: core #12" --repo-dir "$tmp/g/repo" --next "#13 (same session)"
expect "same session: no archive" 0 "PR #7 merged. Next: #13 (same session)"
[[ "$out" != *archive:* && -d "$tmp/g/repo/.claude/worktrees/agent-12" ]] && ok "same session keeps session and worktree" || bad "same session keeps session and worktree" "$out"
echo dirty >"$tmp/g/repo/.claude/worktrees/agent-12/scratch.txt"
case_; run o/r 7 abcdef1 --session $SID --per-issue "Agent: core #12" --repo-dir "$tmp/g/repo"
expect "dirty worktree is kept" 0 "worktree: kept:"
rm "$tmp/g/repo/.claude/worktrees/agent-12/scratch.txt"
case_; run o/r 7 abcdef1 --session $SID --per-issue "Agent: core #12" --repo-dir "$tmp/g/repo"
expect "per-issue: archive line" 0 "archive: Agent: core #12"
[[ -n "${SHOW:-}" ]] && printf '%s\n' "$out"
[[ "$out" == *"send to Agent: core #12: PR #7 merged. Next: done"* ]] && ok "Next line names the author" || bad "Next line names the author" "$out"
[[ "$out" == *"worktree: removed"* && ! -d "$tmp/g/repo/.claude/worktrees/agent-12" ]] && ok "clean pushed worktree removed" || bad "clean pushed worktree removed" "$out"
[[ "$(lines)" -le 6 ]] && ok "per-issue output is at most 6 lines" || bad "per-issue output is at most 6 lines" "$out"
case_; run o/r 7 abcdef1 --session $SID --per-issue "Agent: core #12" --repo-dir "$tmp/g/repo"
expect "no worktree left" 0 "worktree: none for feat/12-x"

# The merge call fails but the PR merged (branch delete failed): merged, noted, Next recorded
case_; touch "$FAKE/merge-landed-fail"; run o/r 7 abcdef1 --session $SID
expect "nonzero gh pr merge on a MERGED PR counts as merged" 0 "merged into develop (merge, abcdef1); gh pr merge exited 1 (failed to delete branch; check the branch was deleted); closed o/r#12"
[[ "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" == "o/r#7" ]] && ok "landed merge records the pending Next" || bad "landed merge records the pending Next" "$out"
# The state lookup fails: unknown, Next recorded anyway, exit 4
case_; touch "$FAKE/state-fail"; run o/r 7 abcdef1 --session $SID
expect "state lookup fails -> state unknown" 4 "merge state unknown (gh pr merge exit 0): check it and send the Next anyway"
[[ "$out" == *"PR #7 merged. Next: done"* && "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" == "o/r#7" ]] \
  && ok "unknown state still records the pending Next and prints the line" || bad "unknown state records the pending Next" "$out"
[[ ! -f "$FAKE/close.log" ]] && ok "unknown state closes no issue" || bad "unknown state closes no issue"

# Merge method: only the value after the colon; a placeholder is unset
for pv in 'Merge method: <merge commit or squash>.:merge' 'Merge method: merge (never squash).:merge' \
          'Merge method: Squash.:squash' 'Merge method: rebase:rebase' \
          'Merge method: `squash`.:squash' 'Merge method: "squash":squash' "Merge method: 'rebase'.:rebase" \
          'Merge method: **squash**:squash' 'Merge method: `<merge commit or squash>`.:merge' \
          '- **Merge method:** squash:squash' '**Merge method:** `rebase`.:rebase'; do
  case_; printf -- '- Integration branch: develop. %s\n' "${pv%:*}" >"$tmp/ledger/coordination/PROFILE.md"
  run o/r 7 abcdef1 --session $SID --ledger "$tmp/ledger"
  expect "profile '${pv%:*}' -> ${pv##*:}" 0 "(${pv##*:}, abcdef1)"
done

# Owner approves merges into: a named base refuses without --owner-approved; none, a
# placeholder or no line lets the coordinator merge (the kit default)
for pv in 'Owner approves merges into: none.:0' 'Owner approves merges into: <none | branch>.:0' \
          'Owner approves merges into: `none` (the coordinator merges).:0' 'Merge method: merge.:0' \
          'Owner approves merges into: develop.:1' 'Owner approves merges into: `main`, `develop`.:1' \
          '**Owner approves merges into:** develop:1' 'Owner approves merges into: main.:0'; do
  case_; printf -- '- Integration branch: develop. %s\n' "${pv%:*}" >"$tmp/ledger/coordination/PROFILE.md"
  run o/r 7 abcdef1 --session $SID --ledger "$tmp/ledger"
  if [[ "${pv##*:}" == 1 ]]; then
    expect "profile '${pv%:*}' refuses develop" 1 "merges into develop need the owner's approval"; nomerge "owner-approved base"
    run o/r 7 abcdef1 --session $SID --ledger "$tmp/ledger" --owner-approved
    expect "profile '${pv%:*}' + --owner-approved merges" 0 "merged into develop"
  else
    expect "profile '${pv%:*}' lets the coordinator merge develop" 0 "merged into develop"
  fi
done

# An unregistered session leaves no state dir behind
case_; run o/r 7 abcdef1 --session typo-sess
[[ ! -e "$COORDINATOR_HOME/state/typo-sess" ]] && ok "unregistered session creates no state dir" || bad "unregistered session creates no state dir"

# The key merge-reminder stores comes from the PR URL; a case-different one is the same PR
case_ feat/12-x develop OPEN agent-bot Owner/Repo
bash "$plugin/scripts/next-clear.sh" $SID --add Owner/Repo#7 >/dev/null
run owner/repo 7 abcdef1 --session $SID
[[ "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" == "Owner/Repo#7" && "$out" == *"PR #7 merged."* ]] \
  && ok "case-different repo arg resolves to the URL key, no duplicate" || bad "case-different key" "$(bash "$plugin/scripts/next-clear.sh" $SID --list; echo "$out")"
printf '{"session_id":"%s","tool_name":"SendMessage","tool_input":{"to":"a","message":"PR owner/repo#7 merged. Next: done"}}' $SID \
  | bash "$plugin/hooks/next-sent.sh" >/dev/null
[[ -z "$(bash "$plugin/scripts/next-clear.sh" $SID --list)" ]] && ok "a lower-case owner/repo#N message clears the URL key" || bad "lower-case message clears the URL key"

echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
