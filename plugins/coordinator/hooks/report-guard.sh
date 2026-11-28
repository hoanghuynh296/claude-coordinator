#!/usr/bin/env bash
# Agent-side Stop hook (#10): no turn end with an open PR the coordinator was never told about.
# Acts only in an agent session of an opted-in unit:
#   - the repo has `git config coordinator.reportTo "Coordinator: <project>"` (set by
#     scripts/install-guards.sh --agent <project>), and
#   - the session is not a registered coordinator, and
#   - the session is an agent of that coordinator: a user message of its transcript (never an
#     attachment such as CLAUDE.md / AGENTS.md, never a tool result) holds the brief's line
#     "Your coordinator is the session **Coordinator: <project>**", or it has sent a report
#     already (report-sent.sh), and
#   - the branch is not an integration or release branch: main, master, develop, release/*,
#     backmerge/*, and those in `git config coordinator.protectedBranches`.
# Then, when the branch has an open PR (gh, 10 s deadline) and no report of this session covers
# its head, the stop is blocked: send `PR ready:` (head, CI state) to the coordinator.
# A report covers the head when it is a `PR ready:` naming the head SHA (7+ hex chars), or a
# `blocked:` / `Draft ready:` / `handover` report sent while that head was the pushed one.
# `Next: done` and `stand by` come after a merge (no open PR) or a reported head, so they pass.
# No gh call when the last report is a `PR ready:` naming the local HEAD and HEAD is pushed.
# At most COORDINATOR_REPORT_MAX_BLOCKS (default 3) blocks per turn, then a warning.
# Fails open: no git, no gh, gh error or timeout, no transcript, no python3 (then only a sent
# report marks an agent), any error -> no output (on Antigravity {"decision":"stop"}).
# COORDINATOR_REPORT_GUARD=off switches it off.
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
branch="$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null)" || silent
[[ -n "$branch" ]] || silent
case "$branch" in main|master|develop|release/*|backmerge/*) silent ;; esac
for p in $(git -C "$top" config --get coordinator.protectedBranches 2>/dev/null); do
  [[ "$branch" == "$p" ]] && silent
done
d="$(state_dir "$sid")" || silent
reports="$d/reports"

# Agent of this coordinator? A sent report, or the brief's line in a user message.
if [[ ! -s "$reports" ]]; then
  command -v python3 >/dev/null 2>&1 || silent
  tr="$(json_get "$input" transcript_path)"
  if [[ -z "$tr" || ! -f "$tr" ]]; then
    tr="${ANTIGRAVITY_BRAIN_DIR:-$HOME/.gemini/antigravity/brain}/$sid/.system_generated/logs/transcript.jsonl"
    if [[ ! -f "$tr" ]]; then
      tr=""
      for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"/*/"$sid".jsonl; do [[ -f "$f" ]] && { tr="$f"; break; }; done
    fi
  fi
  [[ -n "$tr" && -f "$tr" ]] || silent
  python3 -I - "$tr" "$to" <<'PY' 2>/dev/null || silent
import json, re, sys
n = re.escape(sys.argv[2])   # bold as in the brief template, or plain and ending the clause
pat = re.compile(r"Your coordinator is the session (?:\*\*" + n + r"\*\*|" + n + r"(?=[;.,)]|[ \t]*$))", re.M)
def text_of(c):   # a user message's own text; None for tool results
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        return "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return None
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if not isinstance(r, dict):
            continue
        t = None
        if r.get("type") == "user" and not r.get("isMeta") and not r.get("isSidechain"):
            m = r.get("message")
            t = text_of(m.get("content")) if isinstance(m, dict) else None
        elif r.get("type") == "USER_INPUT":   # Antigravity
            t = r.get("content") if isinstance(r.get("content"), str) else None
        if t and pat.search(t):
            sys.exit(0)
sys.exit(1)
PY
fi

head_local="$(git -C "$top" rev-parse -q --verify HEAD 2>/dev/null)" || head_local=""
pushed="$(git -C "$top" rev-parse -q --verify '@{push}' 2>/dev/null)" \
  || pushed="$(git -C "$top" rev-parse -q --verify "refs/remotes/origin/$branch" 2>/dev/null)" || pushed=""
# Reported and pushed: no gh call.
if [[ -n "$head_local" && "$head_local" == "$pushed" && -s "$reports" ]] && tail -n 1 "$reports" | awk -v h="$head_local" '
    $2 == "ready" { for (i = 4; i <= NF; i++) if (index(h, $i) == 1) found = 1 }
    END { exit !found }'; then
  rm -f "$d/report-blocks"; silent
fi

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

# Covered? A PR ready naming the head, or a blocked / draft / handover report sent while the
# head was the pushed one.
if [[ -f "$reports" ]] && awk -v h="$head" '
    $2 == "ready" { for (i = 4; i <= NF; i++) if (index(h, $i) == 1) found = 1 }
    $2 != "ready" && $3 == h { found = 1 }
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
