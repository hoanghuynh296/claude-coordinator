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
kv="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$scripts/../.claude-plugin/plugin.json" | head -n 1)"
if grep -q "^Kit: $kv (" "$w/a/COORDINATION.md"; then pass=$((pass+1)); echo "PASS init-ledger writes the 'Kit: $kv' line (#54)"
else failn=$((failn+1)); echo "FAIL init-ledger 'Kit:' line"; grep -n Kit "$w/a/COORDINATION.md" || true; fi

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

fresh g1; printf '| core | v0.10.0 | 3 PRs, since 2020-01-01; group Phone filters | #5 | nothing |\n' >> "$w/g1/COORDINATION.md"
expect_lint "unit row past the ceiling days is a warning" ok "$w/g1" "safety ceiling"
fresh g2; printf '| core | v0.10.0 | 3 PRs, since %s; group Phone filters | #5 | nothing |\n' "$(date +%Y-%m-%d)" >> "$w/g2/COORDINATION.md"
expect_lint "unit row inside the ceiling is clean" ok "$w/g2" "1 warning(s)"
fresh g3; printf '#### Group Phone filters → v0.11.0 (large)\n#### Group Fixes → v0.10.1 (small)\n' >> "$w/g3/coordination/ROADMAP.md"
expect_lint "sized release groups are accepted" ok "$w/g3" "0 error(s)"
fresh g4; printf '#### Group Phone filters → v0.11.0\n' >> "$w/g4/coordination/ROADMAP.md"
expect_lint "group heading without a size is a warning" ok "$w/g4" "needs its size"
fresh g5; sed -i.bak 's/Integration limit/Release/' "$w/g5/coordination/PROFILE.md"; rm -f "$w/g5/coordination/PROFILE.md.bak"
expect_lint "old and new profile column both lint" ok "$w/g5" "0 error(s)"

fresh g6; printf '## Group findings (first survey)\n' >> "$w/g6/coordination/ROADMAP.md"
expect_lint "non-release heading starting with Group is ignored" ok "$w/g6" "1 warning(s)"
fresh g7; printf '| core | idle since 2020-01-01 | nothing |\n' >> "$w/g7/COORDINATION.md"
expect_lint "non-unit row with an old since-date gives no ceiling warning" ok "$w/g7" "1 warning(s)"

# Finished work (#57): a warning by default, with each line's age, oldest first; an error only
# when the ledger sets FINISHED_DAYS. A line's date: its last commit (git blame), else "Updated:".
days_ago() { python3 -c "import datetime,sys;print(datetime.date.today()-datetime.timedelta(days=int(sys.argv[1])))" "$1"; }
gcommit() { # dir days-ago message
  ( cd "$1" && git add -A && GIT_AUTHOR_DATE="$(days_ago "$2")T12:00:00" GIT_COMMITTER_DATE="$(days_ago "$2")T12:00:00" \
    git -c user.name=t -c user.email=t@t commit -qm "$3" ); }
fresh f1; ( cd "$w/f1" && git init -q . ); gcommit "$w/f1" 30 init
for n in 1 2 3; do echo "- web PR #1$n merged" >> "$w/f1/COORDINATION.md"; done; gcommit "$w/f1" 12 old
for n in 4 5 6; do echo "- web PR #1$n merged" >> "$w/f1/COORDINATION.md"; done; gcommit "$w/f1" 3 newer
expect_lint "default: old finished lines are a warning only" ok "$w/f1" "0 error(s)"
expect_lint "the warning gives each line's age, oldest first" ok "$w/f1" "oldest first: line 3 (30 days), line 36 (12 days)"
printf 'FINISHED_DAYS=7\n' > "$w/f1/.ledger-lint"
expect_lint "FINISHED_DAYS=7: finished item older than 7 days is an error" fail "$w/f1" "COORDINATION.md:36: finished work 12 days old"
expect_lint "the error names the FINISHED_DAYS=0 escape" fail "$w/f1" "set FINISHED_DAYS=0 in .ledger-lint"
expect_lint "template prose (merged PRs) is never an error" fail "$w/f1" "3 error(s)"
out="$(FINISHED_DAYS=20 bash "$scripts/ledger-lint.sh" "$w/f1" 2>&1)" && { pass=$((pass+1)); echo "PASS FINISHED_DAYS from the environment wins"; } \
  || { failn=$((failn+1)); echo "FAIL FINISHED_DAYS env: $out"; }
printf 'FINISHED_DAYS=0\n' > "$w/f1/.ledger-lint"
expect_lint "FINISHED_DAYS=0 keeps it a warning" ok "$w/f1" "0 error(s)"

# Live lines that mention merged/done never error, even with FINISHED_DAYS set and 20 days old.
fresh f2; ( cd "$w/f2" && git init -q . ); printf 'FINISHED_DAYS=7\n' > "$w/f2/.ledger-lint"
cat >> "$w/f2/COORDINATION.md" <<'L'
| core | M3 done | #40, agent | nothing |
- PR #193 merged; the 2nd runner waits on the disk check
- api M2 is not done
- web PR #7 merged, UNVERIFIED on a real phone
- docs merged, next #51
- api PR #9 merged
  waiting on the release tag
## Owner queue (in order)
1. Approve the release after PR #8 merged.
L
gcommit "$w/f2" 20 live
expect_lint "live lines with merged/done are never errors" ok "$w/f2" "0 error(s)"
printf '## Notes\n- app PR #2 merged\n' >> "$w/f2/COORDINATION.md"; gcommit "$w/f2" 20 done
expect_lint "a plain finished item next to them is the one error" fail "$w/f2" "1 error(s)"
# a multi-line item is dated by its newest line
fresh f3; ( cd "$w/f3" && git init -q . ); printf 'FINISHED_DAYS=7\n' > "$w/f3/.ledger-lint"
echo "- api PR #3 merged" >> "$w/f3/COORDINATION.md"; gcommit "$w/f3" 20 old
echo "  and the staging deploy is green" >> "$w/f3/COORDINATION.md"; gcommit "$w/f3" 2 newer
expect_lint "multi-line item dated by its newest line" ok "$w/f3" "0 error(s)"
echo "- api PR #4 merged" >> "$w/f3/COORDINATION.md"
expect_lint "an uncommitted finished item is new" ok "$w/f3" "0 error(s)"
# outside git: dated by "Updated:"
fresh f4; sed -i.bak "s/^Updated: .*/Updated: $(days_ago 9)/" "$w/f4/COORDINATION.md"; rm "$w/f4/COORDINATION.md.bak"
echo "- web PR #12 merged" >> "$w/f4/COORDINATION.md"
expect_lint "outside git, default: no error" ok "$w/f4" "0 error(s)"
printf 'FINISHED_DAYS=7\n' > "$w/f4/.ledger-lint"
expect_lint "outside git, FINISHED_DAYS=7: dated by Updated:" fail "$w/f4" "finished work 9 days old"

# Handover notes over 150 lines or 10k characters are a warning (#57).
fresh h1; for i in $(seq 1 151); do echo "- line $i" >> "$w/h1/coordination/handover/web.md"; done
expect_lint "handover over 150 lines is a warning" ok "$w/h1" "knowledge goes to the unit's docs"
printf 'HANDOVER_MAX_LINES=200\n' > "$w/h1/.ledger-lint"
expect_lint "HANDOVER_MAX_LINES from .ledger-lint" ok "$w/h1" "1 warning(s)"
fresh h2; python3 -c "print('x' * 10001)" > "$w/h2/coordination/handover/coordinator.md"
expect_lint "handover over 10k characters is a warning" ok "$w/h2" "10002 characters"
out="$(HANDOVER_MAX_CHARS=20000 bash "$scripts/ledger-lint.sh" "$w/h2" 2>&1)"
[[ "$out" != *"unit's docs"* ]] && { pass=$((pass+1)); echo "PASS HANDOVER_MAX_CHARS from the environment"; } || { failn=$((failn+1)); echo "FAIL HANDOVER_MAX_CHARS env: $out"; }
fresh h3; for i in $(seq 1 150); do echo "- line $i" >> "$w/h3/coordination/handover/web.md"; done
expect_lint "handover at 150 lines is clean" ok "$w/h3" "1 warning(s)"

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
