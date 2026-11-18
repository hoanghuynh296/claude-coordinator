#!/usr/bin/env bash
# ledger-lint.sh against small ledgers: a fresh one from init-ledger.sh must pass; each rule
# must fire on a ledger that breaks it.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scripts="$root/plugins/coordinator/scripts"
w="$root/tests/.work/lint"; rm -rf "${w:?}"; mkdir -p "$w"

pass=0; failn=0
# expect_lint <name> <ok|fail> <dir> [text the output must contain]
expect_lint() {
  local name="$1" want="$2" dir="$3" needle="${4:-}" out rc=0
  out="$(bash "$scripts/ledger-lint.sh" "$dir" 2>&1)" || rc=$?
  local got=ok; [[ $rc -ne 0 ]] && got=fail
  if [[ "$got" == "$want" && ( -z "$needle" || "$out" == *"$needle"* ) ]]; then
    pass=$((pass+1)); printf 'PASS %-4s %s\n' "$got" "$name"
  else
    failn=$((failn+1)); printf 'FAIL got %s want %s (%s): %s\n%s\n' "$got" "$want" "$needle" "$name" "$out"
  fi
}
fresh() { rm -rf "${w:?}/$1"; bash "$scripts/init-ledger.sh" "$w/$1" --name Demo --owner someone >/dev/null; }

fresh a
expect_lint "fresh ledger" ok "$w/a" "0 error(s)"
expect_lint "fresh profile warns about unfilled fields" ok "$w/a" "fields to fill"

bash "$scripts/init-ledger.sh" "$w/a" --name Other >/dev/null
if grep -q '^# Demo' "$w/a/COORDINATION.md"; then pass=$((pass+1)); echo "PASS init-ledger keeps existing files"
else failn=$((failn+1)); echo "FAIL init-ledger overwrote COORDINATION.md"; fi

rm -rf "$w/ws"; bash "$scripts/init-ledger.sh" "$w/ws" --name Demo --workspace >/dev/null
if grep -qx '!/coordination/' "$w/ws/.gitignore"; then pass=$((pass+1)); echo "PASS --workspace writes .gitignore"
else failn=$((failn+1)); echo "FAIL --workspace .gitignore"; fi

fresh b; rm "$w/b/coordination/ROADMAP.md"
expect_lint "missing file" fail "$w/b" "coordination/ROADMAP.md: missing"

fresh c; for i in $(seq 1 90); do echo "- item $i" >> "$w/c/COORDINATION.md"; done
expect_lint "over the line budget" fail "$w/c" "budget 80"
printf 'MAX_LINES=200\n' > "$w/c/.ledger-lint"
expect_lint "budget from .ledger-lint" ok "$w/c"

fresh d; printf -- '- %s\n' "$(printf 'x%.0s' $(seq 1 300))" >> "$w/d/COORDINATION.md"
expect_lint "long line" fail "$w/d" "line of"

fresh e; sed -i.bak '/^Updated:/d' "$w/e/COORDINATION.md"; rm "$w/e/COORDINATION.md.bak"
expect_lint "no Updated line" fail "$w/e" "no 'Updated: YYYY-MM-DD' line"

fresh f; echo "- agent session local_5f0940bb is busy" >> "$w/f/COORDINATION.md"
expect_lint "session id" fail "$w/f" "session id"

fresh g; echo "Memory lives in /Users/someone/.claude/projects/x" > "$w/g/coordination/memory/note.md"
expect_lint "home path in a memory copy" fail "$w/g" "home path /Users/someone"

fresh h; echo "- waiting on C-042" >> "$w/h/COORDINATION.md"
expect_lint "cited decision without a row" fail "$w/h" "C-042 is cited"
echo "| C-042 | 2026-01-01 | owner | all | Something. |" >> "$w/h/coordination/DECISIONS.md"
expect_lint "decision row added" ok "$w/h"
echo "| C-042 | 2026-01-02 | owner | all | Again. |" >> "$w/h/coordination/DECISIONS.md"
expect_lint "duplicate decision id" fail "$w/h" "more than one row"

fresh i; echo "Project {{PROJECT_NAME}}" >> "$w/i/coordination/ROADMAP.md"
expect_lint "placeholder left" fail "$w/i" "placeholder"

fresh j; sed -i.bak 's/^Updated: .*/Updated: 2020-01-01/' "$w/j/COORDINATION.md"; rm "$w/j/COORDINATION.md.bak"
expect_lint "stale date is a warning" ok "$w/j" "days old"

fresh k; echo "- The owner delegated all decisions to this session." >> "$w/k/COORDINATION.md"
expect_lint "undated delegation is a warning" ok "$w/k" "delegation without a date"

fresh l; for i in 1 2 3 4 5 6 7; do echo "- unit PR $i merged" >> "$w/l/COORDINATION.md"; done
expect_lint "history in the ledger is a warning" ok "$w/l" "live state only"

fresh m; printf '| unit | %s |\n' "$(printf 'x%.0s' $(seq 1 300))" >> "$w/m/COORDINATION.md"
expect_lint "long table row is exempt from the line limit" ok "$w/m" "0 error(s)"
fresh m2; printf 'prose %s\n' "$(printf 'x%.0s' $(seq 1 300))" >> "$w/m2/COORDINATION.md"
expect_lint "long prose line still fails" fail "$w/m2" "budget 240"

fresh n; echo "Waits on other:C-099 from the other ledger." >> "$w/n/COORDINATION.md"
expect_lint "project:C-NNN reference is allowed" ok "$w/n" "0 error(s)"
fresh n2; echo "Waits on C-099." >> "$w/n2/COORDINATION.md"
expect_lint "bare unknown decision id is an error" fail "$w/n2" "C-099 is cited"

fresh m3; printf '| prose that never closes the row %s\n' "$(printf 'x%.0s' $(seq 1 300))" >> "$w/m3/COORDINATION.md"
expect_lint "long prose line starting with | still fails" fail "$w/m3" "budget 240"
fresh n3; echo "See http://h:C-1 for it." >> "$w/n3/COORDINATION.md"
expect_lint "url-like host:C-1 is not a cross-ledger reference" fail "$w/n3" "C-1 is cited"

fresh o; echo "- C-002: use bullets" >> "$w/o/coordination/DECISIONS.md"
expect_lint "decision as a bullet says how to write the row" fail "$w/o" "write a table row"

# stale "Updated:" against the last commit touching COORDINATION.md
fresh p
old="$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=3))')"
sed -i.bak "s/^Updated: .*/Updated: $old/" "$w/p/COORDINATION.md"; rm "$w/p/COORDINATION.md.bak"
( cd "$w/p" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
expect_lint "Updated older than the last commit is a warning" ok "$w/p" "older than its last commit"

# install-guards installs a pre-commit hook that stops a broken ledger
fresh q; ( cd "$w/q" && git init -q . )
bash "$scripts/install-guards.sh" "$w/q" >/dev/null
[[ -x "$w/q/.git/hooks/pre-commit" ]] && { pass=$((pass+1)); echo "PASS install-guards installs the ledger pre-commit hook"; } \
  || { failn=$((failn+1)); echo "FAIL no pre-commit hook in the ledger repo"; }
( cd "$w/q" && git add -A && git -c user.name=t -c user.email=t@t commit -qm ok >/dev/null 2>&1 ) \
  && { pass=$((pass+1)); echo "PASS clean ledger commits"; } || { failn=$((failn+1)); echo "FAIL clean ledger commit was refused"; }
echo "Waits on C-777." >> "$w/q/COORDINATION.md"
( cd "$w/q" && git add -A && git -c user.name=t -c user.email=t@t commit -qm bad >/dev/null 2>&1 ) \
  && { failn=$((failn+1)); echo "FAIL broken ledger was committed"; } || { pass=$((pass+1)); echo "PASS broken ledger commit is refused"; }

# foreign pre-commit hook: refused without --force, other steps still run; --force replaces; idempotent
fresh r; ( cd "$w/r" && git init -q . ); printf '#!/bin/sh\nexit 0\n' > "$w/r/.git/hooks/pre-commit"; chmod +x "$w/r/.git/hooks/pre-commit"
rc=0; bash "$scripts/install-guards.sh" --protect "main" "$w/r" >/dev/null 2>&1 || rc=$?
grep -q 'exit 0' "$w/r/.git/hooks/pre-commit" && [[ $rc -ne 0 && -x "$w/r/.git/hooks/pre-push" && "$(git -C "$w/r" config coordinator.protectedBranches)" == main ]] \
  && { pass=$((pass+1)); echo "PASS foreign pre-commit hook refused (rc!=0), pre-push and --protect still done"; } \
  || { failn=$((failn+1)); echo "FAIL foreign pre-commit hook handling (rc=$rc)"; }
bash "$scripts/install-guards.sh" --force "$w/r" >/dev/null 2>&1
grep -q 'coordinator-kit ledger-lint pre-commit' "$w/r/.git/hooks/pre-commit" && [[ -f "$w/r/.git/hooks/pre-commit.before-coordinator" ]] \
  && { pass=$((pass+1)); echo "PASS --force replaces the foreign pre-commit hook"; } || { failn=$((failn+1)); echo "FAIL --force pre-commit"; }
h1="$(cat "$w/r/.git/hooks/pre-commit")"; rc=0
bash "$scripts/install-guards.sh" "$w/r" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 && "$h1" == "$(cat "$w/r/.git/hooks/pre-commit")" ]] \
  && { pass=$((pass+1)); echo "PASS re-install is idempotent"; } || { failn=$((failn+1)); echo "FAIL re-install (rc=$rc)"; }

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
