#!/usr/bin/env bash
# pre-push-guard.sh with a fake `gh`: blocks a push to a branch whose PR is merged or closed,
# allows new branches and open PRs, fails open when gh cannot answer, honours protected
# branches, and install-guards.sh installs it without clobbering a foreign hook.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scripts="$root/plugins/coordinator/scripts"
w="$root/tests/.work/prepush"; rm -rf "${w:?}"; mkdir -p "$w/bin"

cat > "$w/bin/gh" <<'GH'
#!/usr/bin/env bash
# fake gh: answers `gh pr list --head <branch> ...` from $FAKE_GH_DIR/<branch-with-dashes>
[[ "$1 $2" == "pr list" ]] || exit 1
head=""
while [[ $# -gt 0 ]]; do [[ "$1" == "--head" ]] && head="$2"; shift; done
f="$FAKE_GH_DIR/${head//\//-}"
[[ -f "$f.fail" ]] && exit 1
[[ -f "$f" ]] && cat "$f"
exit 0
GH
chmod +x "$w/bin/gh"
export FAKE_GH_DIR="$w/gh"; mkdir -p "$FAKE_GH_DIR"
printf 'MERGED 12\n' > "$FAKE_GH_DIR/feat-merged"
printf 'CLOSED 13\n' > "$FAKE_GH_DIR/feat-closed"
printf 'OPEN 15\nMERGED 14\n' > "$FAKE_GH_DIR/feat-reopened"
: > "$FAKE_GH_DIR/feat-offline.fail"

git init -q -b main "$w/repo"
git -C "$w/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
sha="$(git -C "$w/repo" rev-parse HEAD)"
zero="0000000000000000000000000000000000000000"

pass=0; failn=0
# run <name> <allow|block> <stdin line> [protected branches]
run() {
  local name="$1" want="$2" line="$3" rc=0
  ( cd "$w/repo" && git config --unset coordinator.protectedBranches 2>/dev/null || true
    [[ -n "${4:-}" ]] && git config coordinator.protectedBranches "$4"
    printf '%s\n' "$line" | PATH="$w/bin:$PATH" bash "$scripts/pre-push-guard.sh" origin url >/dev/null 2>&1 ) || rc=$?
  local got=allow; [[ $rc -ne 0 ]] && got=block
  if [[ "$got" == "$want" ]]; then pass=$((pass+1)); printf 'PASS %-5s %s\n' "$got" "$name"
  else failn=$((failn+1)); printf 'FAIL got %s want %s: %s\n' "$got" "$want" "$name"; fi
}
ref() { printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$sha" "$1" "$zero"; }

run "new branch, no PR"            allow "$(ref feat/new)"
run "branch with a merged PR"      block "$(ref feat/merged)"
run "branch with a closed PR"      block "$(ref feat/closed)"
run "merged before, open again"    allow "$(ref feat/reopened)"
run "gh cannot answer: fail open"  allow "$(ref feat/offline)"
run "deleting a merged branch"     allow "(delete) $zero refs/heads/feat/merged $sha"
run "tag push"                     allow "refs/tags/v1 $sha refs/tags/v1 $zero"
run "protected branch"             block "$(ref main)" "main master"
run "unprotected by default"       allow "$(ref main)"

echo "--- install-guards.sh"
bash "$scripts/install-guards.sh" "$w/repo" >/dev/null
if grep -q "coordinator-kit pre-push guard" "$w/repo/.git/hooks/pre-push" && [[ -x "$w/repo/.git/hooks/pre-push" ]]; then
  pass=$((pass+1)); echo "PASS hook installed and executable"
else failn=$((failn+1)); echo "FAIL hook not installed"; fi
bash "$scripts/install-guards.sh" --protect "main" "$w/repo" >/dev/null
if [[ "$(git -C "$w/repo" config coordinator.protectedBranches)" == "main" ]]; then
  pass=$((pass+1)); echo "PASS reinstall is idempotent and sets protected branches"
else failn=$((failn+1)); echo "FAIL --protect"; fi
git init -q -b main "$w/other"; printf '#!/bin/sh\necho mine\n' > "$w/other/.git/hooks/pre-push"
if bash "$scripts/install-guards.sh" "$w/other" >/dev/null 2>&1; then
  failn=$((failn+1)); echo "FAIL foreign hook overwritten without --force"
else pass=$((pass+1)); echo "PASS foreign hook kept without --force"; fi
bash "$scripts/install-guards.sh" --force "$w/other" >/dev/null
if [[ -f "$w/other/.git/hooks/pre-push.before-coordinator" ]]; then
  pass=$((pass+1)); echo "PASS --force saves the old hook"
else failn=$((failn+1)); echo "FAIL --force did not save the old hook"; fi

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
