#!/usr/bin/env bash
# Agent-side Stop hook (#10): no turn end with an open PR the coordinator was never told about.
# Acts only in an agent session of an opted-in unit:
#   - the repo has `git config coordinator.reportTo "Coordinator: <project>"` (set by
#     scripts/install-guards.sh --agent <project>), and
#   - the session is not a registered coordinator, and
#   - the session is an agent of that coordinator: its transcript names "Coordinator: <project>"
#     (the brief does) or it has sent a report already (report-sent.sh).
# Then, when the current branch has an open PR (gh, 10 s deadline) and no report of this session
# covers its head, the stop is blocked: send `PR ready:` (head, CI state) to the coordinator.
# A report covers the head when it is a `PR ready:` naming the head SHA (7+ hex chars), or a
# `blocked:` / `Draft ready:` / handover report sent after the head commit. `Next: done` and
# `stand by` come after a merge (no open PR) or after a reported head, so they pass.
# At most COORDINATOR_REPORT_MAX_BLOCKS (default 3) blocks per turn, then a warning.
# Fails open: no git, no gh, gh error or timeout, no transcript, any error -> no output (on
# Antigravity {"decision":"stop"}). COORDINATOR_REPORT_GUARD=off switches it off.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
ag=0; is_antigravity "$input" && ag=1
silent() { (( ag )) && printf '{"decision":"stop"}\n'; exit 0; }
[[ "${COORDINATOR_REPORT_GUARD:-}" == off ]] && silent
sid="$(hook_sid "$input")" || silent
registration_file "$sid" >/dev/null && silent

dir="$(json_get "$input" cwd)"
[[ -z "$dir" ]] && dir="$(json_get "$input" workspacePaths.0)"
[[ -n "$dir" && -d "$dir" ]] || dir="$PWD"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || silent
to="$(git -C "$top" config --get coordinator.reportTo 2>/dev/null)" || silent
[[ -n "$to" ]] || silent
d="$(state_dir "$sid")" || silent
reports="$d/reports"

# Agent of this coordinator? A sent report, or the transcript (the brief) names it.
if [[ ! -s "$reports" ]]; then
  tr="$(json_get "$input" transcript_path)"
  if [[ -z "$tr" || ! -f "$tr" ]]; then
    tr="${ANTIGRAVITY_BRAIN_DIR:-$HOME/.gemini/antigravity/brain}/$sid/.system_generated/logs/transcript.jsonl"
    if [[ ! -f "$tr" ]]; then
      tr=""
      for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"/*/"$sid".jsonl; do [[ -f "$f" ]] && { tr="$f"; break; }; done
    fi
  fi
  [[ -n "$tr" && -f "$tr" ]] || silent
  grep -qF -- "$to" "$tr" 2>/dev/null || silent
fi

branch="$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null)" || silent
[[ -n "$branch" ]] || silent
gh="${COORDINATOR_GH:-gh}"
command -v "$gh" >/dev/null 2>&1 || silent
out="$d/report-gh.$$"
( cd "$top" && exec "$gh" pr list --head "$branch" --state open --limit 1 \
    --json number,headRefOid --jq '.[0] | "\(.number) \(.headRefOid)"' ) >"$out" 2>/dev/null &
pid=$!
( sleep "${COORDINATOR_REPORT_GH_TIMEOUT:-10}"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
watch=$!
wait "$pid" 2>/dev/null; rc=$?
kill "$watch" 2>/dev/null
read -r pr head _ <"$out" 2>/dev/null || pr=""
rm -f "$out"
[[ $rc -eq 0 && "$pr" =~ ^[0-9]+$ && "$head" =~ ^[0-9a-fA-F]{40}$ ]] || { rm -f "$d/report-blocks"; silent; }
head="$(printf '%s' "$head" | tr 'A-F' 'a-f')"
short="${head:0:7}"

# Covered? A PR ready naming the head, or a later blocked / draft / handover report.
ct="$(git -C "$top" show -s --format=%ct "$head" 2>/dev/null)"; [[ "$ct" =~ ^[0-9]+$ ]] || ct=0
if [[ -f "$reports" ]] && awk -v h="$head" -v ct="$ct" '
    $2 == "ready" { for (i = 3; i <= NF; i++) if (index(h, $i) == 1) found = 1 }
    $2 != "ready" && $1 + 0 >= ct + 0 { found = 1 }
    END { exit !found }' "$reports"; then
  rm -f "$d/report-blocks"; silent
fi

max="${COORDINATOR_REPORT_MAX_BLOCKS:-3}"; [[ "$max" =~ ^[0-9]+$ ]] || max=3
active="$(json_get "$input" stop_hook_active)"
[[ -z "$active" ]] && active="$(json_get "$input" continuationActive)"
count=0
if [[ "$active" == "true" && -f "$d/report-blocks" ]]; then
  count="$(cat "$d/report-blocks" 2>/dev/null)"; [[ "$count" =~ ^[0-9]+$ ]] || count=0
fi
if (( count >= max )); then
  rm -f "$d/report-blocks"
  msg="Agent: PR #$pr head $short is still not reported to \"$to\"; stop allowed after $max blocks. The coordinator does not know it is ready."
  if (( ag )); then printf '{"decision":"stop","reason":%s}\n' "$(json_string "$msg")"
  else printf '{"systemMessage":%s}\n' "$(json_string "$msg")"; fi
  exit 0
fi
echo $((count + 1)) >"$d/report-blocks"
reason="Agent: PR #$pr (head $short) is open and not reported. Send by message (SendMessage / send_message) to \"$to\" a report whose first line is \"PR ready: #$pr $short, CI <pending|green|red>, local gate green\" (evidence, ending \"Context: <k tokens>\"), and post it as a PR comment too. Blocked instead: first line \"blocked: <what>\". No turn-end note reaches the coordinator."
if (( ag )); then
  printf '{"decision":"continue","reason":%s}\n' "$(json_string "$reason")"
else
  printf '{"decision":"block","reason":%s}\n' "$(json_string "$reason")"
fi
