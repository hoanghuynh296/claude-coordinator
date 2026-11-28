#!/usr/bin/env bash
# Lint, commit, rebase and push a coordination ledger in one call, with one line of output.
# Usage: ledger-commit.sh <ledger-dir> "<commit message>"
#
#   1. runs ledger-lint.sh on <ledger-dir>; on errors prints only the error lines and the
#      summary, commits nothing, exit 1
#   2. stages every change under <ledger-dir> (new, changed and deleted files) and commits it
#      (the pre-commit hook, when installed, runs the lint again)
#   3. `git pull --rebase --autostash` from the branch's upstream, then `git push`
#   4. prints one line:
#        ledger-commit: <sha> pushed to <upstream> (<n> file(s)[, <w> warning(s)])
#        ledger-commit: nothing to commit; <upstream> up to date
#        ledger-commit: <sha> committed; not pushed: no upstream for <branch>
#
# Nothing staged but local commits not yet pushed (an earlier push failed): they are rebased and
# pushed. Works the same from any shell (Claude Code Bash, Antigravity run_command).
#
# Exit: 0 done, 1 lint errors, 2 usage or not a git repo, 3 rebase conflict (rebase aborted,
# the commit stays local), 4 push refused or failed, 5 commit failed (hook or git error).
set -euo pipefail

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
[[ $# -eq 2 && -n "$2" ]] || usage
dir="$1"; msg="$2"
[[ -d "$dir" ]] || { echo "ledger-commit: ledger dir not found: $dir" >&2; exit 2; }
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ledger-commit: not a git repository: $dir" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd -P)"
lint_rc=0
lint_out="$(bash "$here/ledger-lint.sh" "$dir" 2>&1)" || lint_rc=$?
if [[ $lint_rc -ne 0 ]]; then
  if [[ $lint_rc -eq 1 ]]; then
    printf '%s\n' "$lint_out" | grep -E '^(error:|ledger-lint:)' || printf '%s\n' "$lint_out"
    echo "ledger-commit: lint failed; nothing committed"
    exit 1
  fi
  printf '%s\n' "$lint_out" >&2
  exit 2
fi
warns="$(printf '%s\n' "$lint_out" | grep -c '^warning:' || true)"

git -C "$dir" add -A -- . >/dev/null
files="$(git -C "$dir" diff --cached --name-only -- . | wc -l | tr -d ' ')"
committed=0
if [[ "$files" -gt 0 ]]; then
  if ! out="$(git -C "$dir" commit -q -m "$msg" -- . 2>&1)"; then
    printf '%s\n' "$out"
    echo "ledger-commit: commit failed"
    exit 5
  fi
  committed=1
fi
sha="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo none)"
detail="$files file(s)"
[[ "$warns" -gt 0 ]] && detail="$detail, $warns warning(s)"

branch="$(git -C "$dir" symbolic-ref --short -q HEAD || echo HEAD)"
if ! up="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  if [[ $committed -eq 1 ]]; then
    echo "ledger-commit: $sha committed; not pushed: no upstream for $branch ($detail)"
  else
    echo "ledger-commit: nothing to commit; no upstream for $branch"
  fi
  exit 0
fi

if ! out="$(git -C "$dir" pull -q --rebase --autostash 2>&1)"; then
  git -C "$dir" rebase --abort >/dev/null 2>&1 || true
  printf '%s\n' "$out" | tail -5
  echo "ledger-commit: rebase on $up failed (aborted); $sha is committed locally, not pushed: resolve, then run again"
  exit 3
fi
ahead="$(git -C "$dir" rev-list --count "$up..HEAD" 2>/dev/null || echo 1)"
if [[ "$ahead" -eq 0 ]]; then
  echo "ledger-commit: nothing to commit; $up up to date"
  exit 0
fi
sha="$(git -C "$dir" rev-parse --short HEAD)"
[[ $committed -eq 0 ]] && detail="$ahead earlier commit(s)"
if ! out="$(git -C "$dir" push -q 2>&1)"; then
  printf '%s\n' "$out" | tail -5
  echo "ledger-commit: push to $up failed; $sha is committed locally"
  exit 4
fi
echo "ledger-commit: $sha pushed to $up ($detail)"
