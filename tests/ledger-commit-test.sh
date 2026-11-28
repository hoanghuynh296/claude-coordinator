#!/usr/bin/env bash
# ledger-commit.sh against a ledger clone of a local bare repo: lint errors stop it, a clean
# change is committed, rebased and pushed with one line of output, conflicts and refused
# pushes leave the commit local with their own exit codes.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scripts="$root/plugins/coordinator/scripts"
w="$root/tests/.work/ledger-commit"; rm -rf "${w:?}"; mkdir -p "$w"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

pass=0; failn=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2"; return 0; }
# run <dir> <msg>: sets out and rc
run() { rc=0; out="$(bash "$scripts/ledger-commit.sh" "$1" "$2" 2>&1)" || rc=$?; }
# expect <name> <rc> <needle>
expect() {
  if [[ $rc -eq $2 && "$out" == *"$3"* ]]; then ok "$1"; else bad "$1 (rc $rc, want $2, needle '$3')" "$out"; fi
}
lines() { printf '%s\n' "$out" | wc -l | tr -d ' '; }

# A bare origin with a fresh ledger on main, and a clone that tracks it.
setup() {
  local n="$1"
  git init -q --bare -b main "$w/$n.git" 2>/dev/null || { git init -q --bare "$w/$n.git"; git -C "$w/$n.git" symbolic-ref HEAD refs/heads/main; }
  bash "$scripts/init-ledger.sh" "$w/$n-seed" --name Demo --owner someone >/dev/null
  git -C "$w/$n-seed" init -q
  git -C "$w/$n-seed" checkout -q -b main 2>/dev/null || true
  git -C "$w/$n-seed" add -A && git -C "$w/$n-seed" commit -q -m seed
  git -C "$w/$n-seed" push -q "$w/$n.git" main
  git clone -q "$w/$n.git" "$w/$n"
}

# 1. clean change: committed, pushed, one line
setup a
echo "- note one" >> "$w/a/coordination/ROADMAP.md"
echo "new" > "$w/a/coordination/extra.md"
run "$w/a" "ledger: note"
expect "clean change is pushed" 0 "pushed to origin/main (2 file(s), 1 warning(s))"
[[ "$(lines)" == 1 ]] && ok "success prints one line" || bad "success prints one line" "$out"
[[ "$(git -C "$w/a.git" log -1 --format=%s main)" == "ledger: note" ]] && ok "origin has the commit" || bad "origin has the commit"
[[ -z "$(git -C "$w/a" status --porcelain)" ]] && ok "tree clean after" || bad "tree clean after"

# 2. nothing to commit
run "$w/a" "ledger: again"
expect "nothing to commit" 0 "nothing to commit; origin/main up to date"

# 3. deleted file is committed too
rm "$w/a/coordination/extra.md"
run "$w/a" "ledger: drop extra"
expect "deletion is pushed" 0 "pushed to origin/main (1 file(s)"
[[ -z "$(git -C "$w/a.git" ls-tree main coordination/extra.md)" ]] && ok "deletion on origin" || bad "deletion on origin"

# 4. lint errors: only errors printed, nothing committed
before="$(git -C "$w/a" rev-parse HEAD)"
echo "- agent session local_5f0940bb is busy" >> "$w/a/COORDINATION.md"
run "$w/a" "ledger: broken"
expect "lint errors stop it" 1 "lint failed; nothing committed"
[[ "$out" == *"error:"*"session id"* && "$out" != *"warning:"* ]] && ok "only error lines printed" || bad "only error lines printed" "$out"
[[ "$(git -C "$w/a" rev-parse HEAD)" == "$before" && -z "$(git -C "$w/a" diff --cached --name-only)" ]] \
  && ok "nothing committed or staged on lint error" || bad "nothing committed or staged on lint error"
git -C "$w/a" checkout -q -- COORDINATION.md

# 5. remote moved on (other file): rebased, then pushed
git clone -q "$w/a.git" "$w/a2"
echo "- from elsewhere" >> "$w/a2/coordination/DECISIONS.md"
git -C "$w/a2" commit -qam "other" && git -C "$w/a2" push -q
echo "- note two" >> "$w/a/coordination/ROADMAP.md"
run "$w/a" "ledger: note two"
expect "rebases on a moved remote and pushes" 0 "pushed to origin/main (1 file(s)"
[[ "$(git -C "$w/a.git" log -2 --format=%s main | tr '\n' ' ')" == "ledger: note two other " ]] \
  && ok "history is linear" || bad "history is linear" "$(git -C "$w/a.git" log --oneline main)"

# 6. conflict: rebase aborted, commit kept locally, exit 3
git -C "$w/a2" pull -q
echo "- theirs" >> "$w/a2/coordination/ROADMAP.md"
git -C "$w/a2" commit -qam "theirs" && git -C "$w/a2" push -q
echo "- ours" >> "$w/a/coordination/ROADMAP.md"
run "$w/a" "ledger: ours"
expect "conflict exits 3" 3 "is committed locally, not pushed"
[[ ! -d "$w/a/.git/rebase-merge" && ! -d "$w/a/.git/rebase-apply" ]] && ok "rebase aborted" || bad "rebase aborted"
[[ "$(git -C "$w/a" log -1 --format=%s)" == "ledger: ours" ]] && ok "local commit kept" || bad "local commit kept"
git -C "$w/a" reset -q --hard origin/main; git -C "$w/a" pull -q

# 7. earlier unpushed commit (nothing staged): pushed now
echo "- local only" >> "$w/a/coordination/DECISIONS.md"
git -C "$w/a" commit -qam "local only"
run "$w/a" "ledger: unused"
expect "earlier unpushed commit is pushed" 0 "pushed to origin/main (1 earlier commit(s))"

# 8. push refused: exit 4
printf '#!/bin/sh\necho refused by test >&2\nexit 1\n' > "$w/a.git/hooks/pre-receive"; chmod +x "$w/a.git/hooks/pre-receive"
echo "- refused" >> "$w/a/coordination/ROADMAP.md"
run "$w/a" "ledger: refused"
expect "refused push exits 4" 4 "push to origin/main failed"
rm "$w/a.git/hooks/pre-receive"

# 9. no upstream: commit only
bash "$scripts/init-ledger.sh" "$w/solo" --name Solo >/dev/null
git -C "$w/solo" init -q
run "$w/solo" "ledger: first"
expect "no upstream commits only" 0 "committed; not pushed: no upstream"

# 10. with the pre-commit hook from install-guards
setup h
bash "$scripts/install-guards.sh" "$w/h" >/dev/null
echo "- hooked" >> "$w/h/coordination/ROADMAP.md"
run "$w/h" "ledger: hooked"
expect "works with the ledger-lint pre-commit hook" 0 "pushed to origin/main"

# 11. usage and bad dir
rc=0; out="$(bash "$scripts/ledger-commit.sh" "$w/a" 2>&1)" || rc=$?
expect "missing message is usage" 2 "Usage"
run "$w/nope" "x"
expect "missing dir" 2 "not found"
plain="$(mktemp -d "${TMPDIR:-/tmp}/ledger-commit-plain.XXXXXX")"; run "$plain" "x"
expect "not a git repo" 2 "not a git repository"; rm -rf "${plain:?}"

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
