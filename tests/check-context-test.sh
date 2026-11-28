#!/usr/bin/env bash
# check-context.sh against fake transcripts: ok / SOFT / HARD levels, thresholds from the
# environment and from arguments, the context-window cap, roles (title, --role), PROFILE
# Budgets (--profile), and bad input.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$root/plugins/coordinator/scripts/check-context.sh"
w="$root/tests/.work/context"; rm -rf "${w:?}"; mkdir -p "$w/config/projects/p"
export CLAUDE_CONFIG_DIR="$w/config"
unset SOFT_AT HARD_AT ROTATE_AT CONTEXT_WINDOW

pass=0; failn=0
# transcript <session id> <context tokens> [title]: one main turn at that size, then a larger
# sidechain turn that must be ignored
transcript() {
  local f="$w/config/projects/p/$1.jsonl" half=$(($2 / 2))
  {
    [[ -n "${3:-}" ]] && printf '{"type":"custom-title","customTitle":"%s"}\n' "$3"
    printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":%d,"cache_creation_input_tokens":%d}}}\n' "$half" $(($2 - half - 10))
    printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":900000}}}\n'
  } >"$f"
}
# expect <name> <ok|fail> <text the output must contain> <command...>
expect() {
  local name="$1" want="$2" needle="$3" out rc=0; shift 3
  out="$("$@" 2>&1)" || rc=$?
  local got=ok; [[ $rc -ne 0 ]] && got=fail
  if [[ "$got" == "$want" && "$out" == *"$needle"* ]]; then
    pass=$((pass+1)); printf 'PASS %-4s %s\n' "$got" "$name"
  else
    failn=$((failn+1)); printf 'FAIL got %s want %s (%s): %s\n%s\n' "$got" "$want" "$needle" "$name" "$out"
  fi
}

transcript s-small 120000 "Agent: web"
transcript s-soft 250000
transcript s-mid 320000
transcript s-hard 400000
printf '{"type":"user","message":{"content":"hi"}}\n' >"$w/config/projects/p/s-new.jsonl"

expect "under soft is ok"            ok   "s-small   120k / soft 250k: ok    Agent: web" bash "$script" s-small
expect "sidechain turns are ignored" ok   " 120k / soft 250k: ok"  bash "$script" s-small
expect "at soft is SOFT"             ok   "s-soft   250k / soft 250k: SOFT"  bash "$script" s-soft
expect "between is SOFT"             ok   "s-mid   320k / soft 250k: SOFT"   bash "$script" s-mid
expect "at hard is HARD"             ok   "s-hard   400k / hard 400k: HARD"  bash "$script" s-hard
expect "transcript path works"       ok   "s-hard   400k / hard 400k: HARD"  bash "$script" "$w/config/projects/p/s-hard.jsonl"
expect "no usage yet"                ok   "s-new  no usage yet"  bash "$script" s-new
expect "no args lists recent"        ok   "s-mid"                bash "$script"
expect "unknown session"             fail "no transcript for nope" bash "$script" nope

expect "SOFT_AT from env"            ok   " 120k / soft 100k: SOFT" env SOFT_AT=100k bash "$script" s-small
expect "ROTATE_AT still sets soft"   ok   " 120k / soft 100k: SOFT" env ROTATE_AT=100000 bash "$script" s-small
expect "HARD_AT from env"            ok   " 320k / hard 300k: HARD" env HARD_AT=300k bash "$script" s-mid
expect "args win over env"           ok   " 320k / soft 330k: ok"   env SOFT_AT=100k bash "$script" --soft 330k --hard 500k s-mid
expect "window caps hard at 75%"     ok   " 320k / hard 300k: HARD" bash "$script" --window 400k s-mid
expect "200k window, default soft"   ok   " 120k / soft 100k: SOFT" bash "$script" --window 200k s-small
expect "200k window caps hard too"   ok   " 250k / hard 150k: HARD" bash "$script" --window 200k s-soft
transcript s-tiny 90000
expect "200k window under soft"      ok   "  90k / soft 100k: ok"   env CONTEXT_WINDOW=200k bash "$script" s-tiny
expect "window above hard changes nothing" ok " 320k / soft 250k: SOFT" bash "$script" --window 1m s-mid
expect "CONTEXT_WINDOW from env"     ok   " 320k / hard 300k: HARD" env CONTEXT_WINDOW=400000 bash "$script" s-mid
expect "--coordinator: 320k is SOFT"  ok   " 320k / soft 300k: SOFT" bash "$script" --coordinator s-mid
expect "--coordinator: 250k is ok"    ok   " 250k / soft 300k: ok"   bash "$script" --coordinator s-soft
expect "--coordinator: 400k is SOFT"  ok   " 400k / soft 300k: SOFT" bash "$script" --coordinator s-hard
expect "--coordinator over env"       ok   " 320k / soft 300k: SOFT" env SOFT_AT=100k HARD_AT=200k bash "$script" --coordinator s-mid
expect "--soft wins over --coordinator" ok " 320k / soft 330k: ok"   bash "$script" --soft 330k --coordinator s-mid

# Role: a "Coordinator: ..." title is a coordinator by default; --role sets it for all.
transcript s-coord 334000 "Coordinator: sme-hub"
transcript s-coord-hard 460000 "Coordinator: web"
expect "Coordinator title: coordinator thresholds" ok "s-coord   334k / soft 300k: SOFT  Coordinator: sme-hub" bash "$script" s-coord
expect "Coordinator title: 460k is HARD"   ok " 460k / hard 450k: HARD" bash "$script" s-coord-hard
expect "agent title keeps agent thresholds" ok "s-small   120k / soft 250k: ok" bash "$script" s-small s-coord
expect "mixed run: coordinator line"       ok "s-coord   334k / soft 300k: SOFT" bash "$script" s-small s-coord
expect "--role agent over the title"       ok " 334k / soft 250k: SOFT" bash "$script" --role agent s-coord
expect "--role coordinator"                ok " 320k / soft 300k: SOFT" bash "$script" --role coordinator s-mid
expect "--role agent: 400k is HARD"        ok " 400k / hard 400k: HARD" bash "$script" --role agent s-hard
expect "SOFT_AT does not touch coordinators" ok " 334k / soft 300k: SOFT" env SOFT_AT=100k bash "$script" s-coord
expect "unknown role is refused"           fail "unknown role" bash "$script" --role owner s-mid

# --profile: thresholds from the ledger's PROFILE.md Budgets section.
mkdir -p "$w/ledger/coordination"
cat >"$w/ledger/coordination/PROFILE.md" <<'MD'
# Profile

## 3. Units

- Same-session cap, soft: 175k must not be read (another section).

## 8. Budgets

- Context, soft: 200k. Past it a session takes no new issue, finishes the current one (PR,
  gate green). Hard: 350k, or 75% of the model's context window if lower.
- Coordinator (group C-015): soft 340k, hard 500k. Agents keep 250k / 400k.
- Same-session cap (`per-issue` units): 175k.

## 9. Deploy

- soft 1k, hard 2k (not Budgets).
MD
expect "profile: agent soft from Budgets"   ok " 320k / soft 200k: SOFT" bash "$script" --profile "$w/ledger/coordination/PROFILE.md" s-small s-mid
expect "profile: agent hard from Budgets"   ok " 400k / hard 350k: HARD" bash "$script" --profile "$w/ledger" s-hard
expect "profile: ledger folder"             ok " 120k / soft 200k: ok"   bash "$script" --profile "$w/ledger" s-small
expect "profile: coordinator soft"          ok " 334k / soft 340k: ok"   bash "$script" --profile "$w/ledger" s-coord
expect "profile: coordinator hard"          ok " 460k / soft 340k: SOFT" bash "$script" --profile "$w/ledger" s-coord-hard
expect "profile: --soft still wins"         ok " 334k / soft 330k: SOFT" bash "$script" --profile "$w/ledger" --soft 330k s-coord
expect "profile: SOFT_AT wins for agents"   ok " 320k / soft 330k: ok"   env SOFT_AT=330k bash "$script" --profile "$w/ledger" s-mid
cat >"$w/ledger/PROFILE-mixed.md" <<'MD'
## Budgets

- Context, soft: agents 260k, coordinator 310k (group C-015). Past it a session takes no new
  issue.
- Context, hard: agents 410k, coordinator 470k (group C-015).
MD
expect "profile: roles inside one bullet (agent)" ok " 320k / soft 260k: SOFT" bash "$script" --profile "$w/ledger/PROFILE-mixed.md" s-mid
expect "profile: roles inside one bullet (coord)" ok " 460k / soft 310k: SOFT" bash "$script" --profile "$w/ledger/PROFILE-mixed.md" s-coord-hard
printf '# Profile\n\n## 1. Product\n\nNo budgets here.\n' >"$w/ledger/PROFILE-none.md"
expect "profile without Budgets: kit defaults" ok " 334k / soft 300k: SOFT" bash "$script" --profile "$w/ledger/PROFILE-none.md" s-coord
expect "kit template parses to the defaults" ok " 320k / soft 250k: SOFT" bash "$script" --profile "$root/plugins/coordinator/skills/coordinator/references/templates/PROFILE.md" s-mid
expect "kit template: coordinator defaults"  ok " 460k / hard 450k: HARD" bash "$script" --profile "$root/plugins/coordinator/skills/coordinator/references/templates/PROFILE.md" s-coord-hard
expect "missing profile is refused"          fail "no profile at" bash "$script" --profile "$w/nope.md" s-mid
mkdir -p "$w/empty-ledger"
expect "ledger folder without PROFILE.md"    fail "no PROFILE.md in" bash "$script" --profile "$w/empty-ledger" s-mid

expect "hard below soft is refused"  fail "below soft" bash "$script" --soft 300k --hard 200k s-mid
expect "bad number is refused"       fail "not a token count" bash "$script" --soft lots s-mid
expect "inf is refused"              fail "not a token count" bash "$script" --soft inf s-mid
expect "unknown option is refused"   fail "unknown option" bash "$script" --rotate 1 s-mid

mkdir -p "$w/ag-brain/ag-conv-1/.system_generated/logs"
{
  printf '{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"hi"}\n'
  printf '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","input_tokens":50000,"cache_read_tokens":210000,"output_tokens":300}\n'
} >"$w/ag-brain/ag-conv-1/.system_generated/logs/transcript.jsonl"
export ANTIGRAVITY_BRAIN_DIR="$w/ag-brain"
expect "Antigravity conversation id" ok   "ag-conv-1   260k / soft 250k: SOFT" bash "$script" ag-conv-1
expect "Antigravity transcript path" ok   "ag-conv-1   260k / soft 300k: ok"   bash "$script" --coordinator "$w/ag-brain/ag-conv-1/.system_generated/logs/transcript.jsonl"

echo "$pass passed, $failn failed"
[[ $failn -eq 0 ]]
