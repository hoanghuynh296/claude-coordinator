#!/usr/bin/env bash
# scripts/prune-worktrees.sh against a local bare remote: dirty, untracked, unpushed, live
# session, young, locked and stray worktrees are kept; a clean pushed old one is removed
# (only with --apply), its branch kept; with --sessions, a branch with an open PR or a live
# session on it is kept, and a failed PR lookup keeps it; --discard globs; a root path with a
# space; argument errors.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$root/plugins/coordinator/scripts/prune-worktrees.sh"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; }
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
q() { "$@" >/dev/null 2>&1; }

git init -q --bare -b main "$tmp/origin.git" 2>/dev/null || { git init -q --bare "$tmp/origin.git"; git -C "$tmp/origin.git" symbolic-ref HEAD refs/heads/main; }
q git clone "$tmp/origin.git" "$tmp/dev root/repo"
R="$tmp/dev root/repo"; W="$R/.claude/worktrees"
# origin looks like GitHub (o/r) for the PR lookup; git still pushes to the local bare repo.
git -C "$R" config url."$tmp/origin.git".insteadOf https://github.com/o/r.git
git -C "$R" remote set-url origin https://github.com/o/r.git
# Fake gh: `pr list -R o/r --head <b>` prints 1 when <b> is a line of $tmp/open-prs, else 0;
# $tmp/gh-fail present -> exit 1.
cat >"$tmp/gh" <<GH
#!/usr/bin/env bash
[[ -f "$tmp/gh-fail" ]] && { echo "HTTP 502" >&2; exit 1; }
[[ "\$1 \$2 \$3 \$4" == "pr list -R o/r" ]] || { echo "unexpected: \$*" >&2; exit 1; }
br=""; while [[ \$# -gt 0 ]]; do [[ "\$1" == --head ]] && br="\$2"; shift; done
grep -qxF -- "\$br" "$tmp/open-prs" 2>/dev/null && echo 1 || echo 0
GH
chmod +x "$tmp/gh"; export COORDINATOR_GH="$tmp/gh"; : >"$tmp/open-prs"
q git -C "$R" checkout -b main
echo a >"$R/a.txt"; echo 'node_modules/' >"$R/.gitignore"; q git -C "$R" add -A; q git -C "$R" commit -m init; q git -C "$R" push -u origin main

# mk <name>: a worktree on a new branch with one commit, pushed.
mk() { q git -C "$R" worktree add "$W/$1" -b "b/$1" main
       echo "$1" >"$W/$1/f.txt"; q git -C "$W/$1" add f.txt; q git -C "$W/$1" commit -m "$1"
       q git -C "$W/$1" push -u origin "b/$1"; }
# age <path>: make the worktree and its git-dir state look 2 days old.
age() { local g; g="$(git -C "$1" rev-parse --absolute-git-dir)"
        find "$1" "$g" -exec touch -t 202601010000 {} + 2>/dev/null; }

mk clean; age "$W/clean"
mk dirty; echo changed >>"$W/dirty/a.txt"; age "$W/dirty"
mk untracked; echo x >"$W/untracked/new.txt"; age "$W/untracked"
mk unpushed; echo more >"$W/unpushed/f.txt"; q git -C "$W/unpushed" commit -am more; age "$W/unpushed"
mk live; mkdir -p "$W/live/sub"; age "$W/live"
mk archived; age "$W/archived"
mk young
mk locked; q git -C "$R" worktree lock "$W/locked"; age "$W/locked"
mk gen; mkdir -p "$W/gen/apps/web"; echo gen >"$W/gen/apps/web/AGENTS.md"; age "$W/gen"
mk genplus; mkdir -p "$W/genplus/apps/web"; echo gen >"$W/genplus/apps/web/AGENTS.md"; echo x >"$W/genplus/other.txt"; age "$W/genplus"
mk ignored; mkdir -p "$W/ignored/node_modules/x"; echo x >"$W/ignored/node_modules/x/i.js"; age "$W/ignored"
mk openpr; age "$W/openpr"; echo b/openpr >>"$tmp/open-prs"
mk sessbr; age "$W/sessbr"
mk sessmerged; age "$W/sessmerged"
q git -C "$R" worktree add --detach "$W/detached" main; age "$W/detached"
mkdir -p "$W/stray-folder"; echo x >"$W/stray-folder/file"; age "$W/stray-folder" 2>/dev/null
touch -t 202601010000 "$W/stray-folder" "$W/stray-folder/file"

cat >"$tmp/sessions.json" <<JSON
[{"sessionId":"a","cwd":"$W/live/sub","isArchived":false},
 {"sessionId":"b","cwd":"$W/archived","isArchived":true},
 {"sessionId":"c","cwd":"$tmp/elsewhere","isArchived":false},
 {"sessionId":"d","cwd":"$tmp","branch":"b/sessbr","prState":"OPEN","isArchived":false},
 {"sessionId":"e","cwd":"$tmp","branch":"b/sessmerged","prState":"MERGED","isArchived":false}]
JSON

run() { out="$(cd "$tmp" && bash "$script" "$@" 2>&1)"; rc=$?; }
has() { [[ "$out" == *"$1"* ]]; }
line_for() { printf '%s\n' "$out" | grep -F -e " $W/$1 " -e " $W/$1:" | head -1; }
expect_line() { # name prefix worktree [needle]
  local l; l="$(line_for "$3")"
  if [[ "$l" == "$2 $W/$3"* && "$l" == *"${4:-}"* ]]; then ok "$1"; else bad "$1 (got: $l)"; fi; }

# Dry run (the default): nothing removed.
run "$tmp/dev root" --sessions "$tmp/sessions.json"
[[ $rc -eq 0 ]] && ok "dry run exits 0" || bad "dry run rc $rc: $out"
expect_line "dry run: clean pushed old -> WOULD REMOVE" "WOULD REMOVE" clean
[[ -d "$W/clean" ]] && ok "dry run removes nothing" || bad "dry run removed clean"
has "would free" && ok "dry run summary says would free" || bad "summary: $out"

# Apply.
run "$tmp/dev root" --sessions "$tmp/sessions.json" --apply
[[ $rc -eq 0 ]] && ok "apply exits 0" || bad "apply rc $rc: $out"
expect_line "clean pushed old -> REMOVE" "REMOVE" clean
[[ ! -d "$W/clean" ]] && ok "clean worktree is gone" || bad "clean worktree still there"
git -C "$R" rev-parse -q --verify refs/heads/b/clean >/dev/null && ok "its branch is kept" || bad "branch b/clean deleted"
expect_line "dirty tracked file -> KEEP" "KEEP" dirty "uncommitted changes"
expect_line "untracked file -> KEEP" "KEEP" untracked "uncommitted changes"
expect_line "unpushed commit -> KEEP" "KEEP" unpushed "unpushed"
expect_line "live session in a subfolder -> KEEP" "KEEP" live "live session"
expect_line "archived session does not block -> REMOVE" "REMOVE" archived
expect_line "young -> KEEP" "KEEP" young "modified in the last 6h"
expect_line "locked -> KEEP" "KEEP" locked "locked"
expect_line "generated file without --discard -> KEEP" "KEEP" gen "uncommitted changes"
expect_line "ignored files only -> REMOVE" "REMOVE" ignored
expect_line "branch with an open PR -> KEEP" "KEEP" openpr "open PR"
expect_line "live session on the branch, PR open -> KEEP" "KEEP" sessbr "live session is on branch b/sessbr"
expect_line "session on the branch, PR merged -> REMOVE" "REMOVE" sessmerged
expect_line "detached HEAD on a pushed commit -> REMOVE" "REMOVE" detached
expect_line "stray folder -> STRAY, not deleted" "STRAY" stray-folder
[[ -f "$W/stray-folder/file" ]] && ok "stray folder still there" || bad "stray folder deleted"
for w in dirty untracked unpushed live young locked gen genplus openpr sessbr; do
  [[ -d "$W/$w" ]] || bad "$w was deleted"
done
[[ "$(cat "$W/dirty/a.txt")" == *changed* ]] && ok "dirty change survives" || bad "dirty change lost"
has "freed" && ok "summary prints the space freed" || bad "summary: $out"

# --discard: only when every change matches.
run "$tmp/dev root" --sessions "$tmp/sessions.json" --apply --discard 'apps/*/AGENTS.md'
expect_line "every change matches --discard -> REMOVE" "REMOVE" gen "discarding 1 generated"
expect_line "one change outside --discard -> KEEP" "KEEP" genplus "other.txt"
[[ -f "$W/genplus/other.txt" ]] && ok "partial match keeps every file" || bad "genplus files lost"

# A failed PR lookup keeps the worktree.
mk ghfail; age "$W/ghfail"; touch "$tmp/gh-fail"
run "$tmp/dev root" --sessions "$tmp/sessions.json" --apply
expect_line "PR lookup fails -> KEEP" "KEEP" ghfail "PR lookup for b/ghfail failed"
rm -f "$tmp/gh-fail"

# --min-age-hours 0 lets a young clean pushed worktree go; --no-session-check also lets the
# live one go (it skips every live check).
run "$tmp/dev root" --no-session-check --apply --min-age-hours 0
expect_line "--min-age-hours 0 -> young REMOVE" "REMOVE" young
expect_line "--no-session-check still keeps dirty" "KEEP" dirty
[[ -d "$W/live" ]] && bad "live removed with --no-session-check" || ok "--no-session-check skips the session check"

# A root that is one worktree checks only that worktree.
mk one; mk two
run "$W/one" --no-session-check --apply --min-age-hours 0
expect_line "root = one worktree -> only it REMOVE" "REMOVE" one
[[ -d "$W/two" && "$out" != *"$W/two"* ]] && ok "root = one worktree leaves the others alone" || bad "two touched: $out"

# Running from inside a worktree keeps it.
mk inside; age "$W/inside"
out="$(cd "$W/inside" && bash "$script" "$tmp/dev root" --no-session-check --apply 2>&1)"
expect_line "current directory -> KEEP" "KEEP" inside "current directory"

# Argument errors.
run "$tmp/dev root"
[[ $rc -eq 2 && "$out" == *"--no-session-check"* ]] && ok "no session option -> exit 2" || bad "no session option rc $rc: $out"
run "$tmp/dev root" --sessions "$tmp/sessions.json" --no-session-check
[[ $rc -eq 2 ]] && ok "both session options -> exit 2" || bad "both rc $rc"
echo '[{"sessionId":"x","title":"no cwd"}]' >"$tmp/nofields.json"
run "$tmp/dev root" --sessions "$tmp/nofields.json"
[[ $rc -eq 2 && "$out" == *"no cwd or branch field"* ]] && ok "sessions without cwd/branch -> exit 2" || bad "nofields rc $rc: $out"
echo '[]' >"$tmp/empty.json"
run "$tmp/dev root" --sessions "$tmp/empty.json"
[[ $rc -eq 0 ]] && ok "empty session list is valid" || bad "empty list rc $rc: $out"
echo 'not json' >"$tmp/bad.json"
run "$tmp/dev root" --sessions "$tmp/bad.json"
[[ $rc -eq 2 && "$out" == *"not list_sessions JSON"* ]] && ok "bad sessions file -> exit 2" || bad "bad json rc $rc: $out"
run "$tmp/dev root" --no-session-check --min-age-hours x
[[ $rc -eq 2 ]] && ok "bad --min-age-hours -> exit 2" || bad "bad age rc $rc"
run --no-session-check
[[ $rc -eq 2 ]] && ok "no root -> usage, exit 2" || bad "no root rc $rc"

echo "prune-worktrees: $pass passed, $failn failed"
[[ $failn -eq 0 ]]
