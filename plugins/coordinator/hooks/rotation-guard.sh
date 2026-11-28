#!/usr/bin/env bash
# Rotation guard (#47). UserPromptSubmit / PreInvocation hook, and Stop hook, of a registered
# coordinator. It measures the coordinator's own context from its transcript with
# scripts/check-context.sh --role coordinator --profile <ledger> --porcelain (PROFILE Budgets,
# else the kit defaults 300k / 450k), so the coordinator spends no tool call on it.
#   below soft   no output, ever
#   past soft    every owner turn gets one line: "Coordinator at <k>k / soft <s>k: rotate now
#                (procedure handover.md, then a replacement)"; with background subagents still
#                running it says to wait for them first
#   past hard    the prompt line says to rotate in this turn, and the Stop hook blocks the end of
#                an owner-started turn until coordination/handover/coordinator.md was committed
#                in this session (on Remote Control the coordinator also makes the rotation the
#                first Owner queue item; the handover is what lifts the block). Let through:
#                - a merge in flight (pending Next, or a ci-watch.sh running in the background):
#                  once, with the reminder (the same turn stays let through; not without a
#                  readable turn id, as on Antigravity)
#                - background subagents still running: the first stop of the turn is blocked
#                  with their names; the next one is let through so the turn can end and wait
#                  for their reports (or they go into the handover as "running: <agent>, <task>")
#                - at most COORDINATOR_ROTATE_MAX_BLOCKS (default 3) blocks per turn
#                - turns that the owner did not start (task notifications, peer messages)
# Fail-open: no python3, no transcript, an unreadable profile, a failed transcript scan (Stop)
# or any error gives no output (on
# Antigravity the neutral answer). Unregistered sessions: no output.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

here="$(cd "$(dirname "$0")" && pwd -P)"
plugin="$(cd "$here/.." && pwd -P)"
input="$(cat)"
ag=0; is_antigravity "$input" && ag=1
event="$(json_get "$input" hook_event_name)"
[[ -z "$event" ]] && event="$(json_get "$input" hookEventName)"
# Mode: the first argument (prompt | stop, as hooks.json passes it), else the event name.
case "${1:-}:$event" in
  stop:*|:Stop) mode=stop ;;
  prompt:*|:UserPromptSubmit|:PreInvocation) mode=prompt ;;
  *) exit 0 ;;
esac
silent() {
  if (( ag )); then
    if [[ "$mode" == stop ]]; then printf '{"decision":"stop"}\n'; else printf '{}\n'; fi
  fi
  exit 0
}
command -v python3 >/dev/null 2>&1 || silent
sid="$(hook_sid "$input")" || silent
reg="$(registration_file "$sid")" || silent
ledger="$(reg_value "$reg" ledger)"
[[ -n "$ledger" && -d "$ledger" ]] || silent

# The transcript: the hook's transcript_path, else the session's file (Claude Code projects or
# the Antigravity brain folder).
tr="$(json_get "$input" transcript_path)"
if [[ -z "$tr" || ! -f "$tr" ]]; then
  tr="${ANTIGRAVITY_BRAIN_DIR:-$HOME/.gemini/antigravity/brain}/$sid/.system_generated/logs/transcript.jsonl"
  if [[ ! -f "$tr" ]]; then
    tr=""
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"/*/"$sid".jsonl; do [[ -f "$f" ]] && { tr="$f"; break; }; done
  fi
fi
[[ -n "$tr" && -f "$tr" ]] || silent

# Thresholds: the ledger's PROFILE Budgets when it has a readable one, else the kit defaults.
# CONTEXT_WINDOW, SOFT_AT and HARD_AT are not the coordinator's: they are cleared for the call.
cc() { env -u CONTEXT_WINDOW -u SOFT_AT -u HARD_AT -u ROTATE_AT bash "$plugin/scripts/check-context.sh" --role coordinator --porcelain "$@" "$tr" 2>/dev/null; }
line="$(cc --profile "$ledger")" || line="$(cc)" || silent
read -r _ ctx soft hard level _ <<<"$line"
[[ "$ctx" =~ ^[0-9]+$ && "$soft" =~ ^[0-9]+$ && "$hard" =~ ^[0-9]+$ ]] || silent
d="$(state_dir "$sid")" || silent
if [[ "$level" != SOFT && "$level" != HARD ]]; then
  rm -f "$d/rotation-blocks" "$d/rotation-letthrough"
  silent
fi
k() { echo "$(( $1 / 1000 ))k"; }

# One pass over the transcript (only past soft): who started the current turn, when the session
# started, which background subagents and ci-watch runs are still running. Antigravity
# transcripts carry none of this: owner turn assumed, nothing running.
scan="$(python3 -I - "$tr" <<'PY' 2>/dev/null
import json, re, sys
launched, done, start, turn, owner = {}, set(), "", "", "1"
notice = re.compile(r"^\s*<(task-notification|cross-session-message|side-sessions-event|ci-monitor-event|[a-z]+(?:-[a-z]+)*-(?:event|notification|message))\b")
def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        t = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(t) if t else None
    return None
def flat(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(flat(x) for x in c)
    if isinstance(c, dict):
        return flat(c.get("text", "")) if "text" in c else ""
    return ""
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if "<task-notification>" in line:
            done.update(re.findall(r"<task-id>([^<]+)</task-id>", line))
            done.update(re.findall(r"<tool-use-id>([^<]+)</tool-use-id>", line))
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if not isinstance(rec, dict):
            continue
        if not start and isinstance(rec.get("timestamp"), str):
            start = rec["timestamp"]
        if rec.get("isSidechain"):
            continue
        msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
        content = msg.get("content")
        if rec.get("type") == "assistant" and isinstance(content, list):
            for b in content:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                if b.get("name") in ("Agent", "Task"):
                    what = inp.get("description") or inp.get("subagent_type") or "subagent"
                    launched[b.get("id")] = ["agent", str(inp.get("subagent_type") or "agent"), str(what), None]
                elif b.get("name") == "Bash" and inp.get("run_in_background") and "ci-watch.sh" in str(inp.get("command", "")):
                    launched[b.get("id")] = ["ciwatch", "ci-watch", "", None]
        elif rec.get("type") == "user" and isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in launched:
                    t = flat(b.get("content"))
                    kind = launched[b["tool_use_id"]][0]
                    if kind == "agent":   # only an async launch runs on; a foreground result is the report
                        m = re.search(r"Async agent launched.*?agentId:\s*([A-Za-z0-9_-]+)", t, re.S)
                    else:
                        m = re.search(r"running in background with ID:\s*([A-Za-z0-9_-]+)", t)
                    if m:
                        launched[b["tool_use_id"]][3] = m.group(1)
                    else:
                        launched.pop(b["tool_use_id"], None)   # ran in the foreground, finished
        if rec.get("type") == "user" and not rec.get("isMeta") and not rec.get("isCompactSummary"):
            t = text_of(content)
            if t is None or t.lstrip().startswith("Stop hook feedback"):
                continue
            o = rec.get("origin")
            if isinstance(o, dict) and o.get("kind"):
                owner = "1" if o.get("kind") == "human" else "0"
            else:
                owner = "0" if notice.match(t) else "1"
            turn = str(rec.get("uuid") or rec.get("timestamp") or "")
print(f"owner={owner}")
print(f"turn={re.sub(r'[^A-Za-z0-9_.:-]', '', turn)}")
print(f"start={re.sub(r'[.][0-9]+', '', start)}")
for tid, (kind, who, what, task) in launched.items():
    if task and task not in done and tid not in done:
        what = re.sub(r"[\r\n\t]+", " ", what)[:60]
        print(f"{kind}={who}: {what}" if kind == "agent" else "ciwatch=1")
PY
)" || scan="failed=1"
owner="$(sed -n 's/^owner=//p' <<<"$scan" | head -n 1)"; [[ -n "$owner" ]] || owner=1
turn="$(sed -n 's/^turn=//p' <<<"$scan" | head -n 1)"; [[ -n "$turn" ]] || turn=none
start="$(sed -n 's/^start=//p' <<<"$scan" | head -n 1)"
[[ -n "$start" ]] || start="$(reg_value "$reg" registered)"   # transcripts without timestamps
agents="$(sed -n 's/^agent=//p' <<<"$scan" | awk 'NF' | paste -sd ';' - | sed 's/;/; /g')"
ciwatch="$(grep -c '^ciwatch=' <<<"$scan" || true)"

if [[ "$mode" == prompt ]]; then
  text="$(json_get "$input" prompt)"; [[ -z "$text" ]] && text="$(json_get "$input" lastUserInput)"
  [[ "$text" =~ ^[[:space:]]*\<(task-notification|cross-session-message|side-sessions-event|ci-monitor-event)  ]] && silent
  if [[ "$level" == HARD ]]; then
    msg="Coordinator at $(k "$ctx") / hard $(k "$hard"): rotate in this turn (procedure handover.md, then a replacement); the end of this turn is blocked until coordination/handover/coordinator.md is committed."
  else
    msg="Coordinator at $(k "$ctx") / soft $(k "$soft"): rotate now (procedure handover.md, then a replacement)"
  fi
  [[ -n "$agents" ]] && msg+="; first wait for the background subagent(s) still running: $agents"
  if (( ag )); then
    printf '{"injectSteps":[{"systemMessage":{"systemMessage":%s}}]}\n' "$(json_string "$msg")"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$(json_string "$msg")"
  fi
  exit 0
fi

# Stop: only at hard, only at the end of a turn the owner started; a failed scan fails open.
[[ "$scan" == failed=1 ]] && silent
[[ "$level" == HARD && "$owner" == 1 ]] || silent
done_in_session() { # path relative to the ledger: in HEAD and committed since the session started?
  [[ -n "$start" ]] || return 1
  git -C "$ledger" cat-file -e "HEAD:./$1" 2>/dev/null || return 1
  [[ -n "$(git -C "$ledger" log -1 --since="$start" --format=%h -- "$1" 2>/dev/null)" ]]
}
if done_in_session coordination/handover/coordinator.md || done_in_session handover/coordinator.md; then
  rm -f "$d/rotation-blocks" "$d/rotation-letthrough"; silent
fi

allow() { # message: let the stop through with a warning
  if (( ag )); then printf '{"decision":"stop","reason":%s}\n' "$(json_string "$1")"
  else printf '{"systemMessage":%s}\n' "$(json_string "$1")"; fi
  exit 0
}
head="Coordinator at $(k "$ctx") / hard $(k "$hard"): rotate in this turn"
# Blocks in this turn: counted while stop_hook_active is true (as next-guard.sh does).
active="$(json_get "$input" stop_hook_active)"
[[ -z "$active" ]] && active="$(json_get "$input" continuationActive)"
count=0
if [[ "$active" == "true" && -f "$d/rotation-blocks" ]]; then
  count="$(cat "$d/rotation-blocks" 2>/dev/null)"; [[ "$count" =~ ^[0-9]+$ ]] || count=0
fi
if [[ -n "$agents" ]] && (( count >= 1 )); then
  allow "$head once the background subagent(s) have reported: $agents. Stop let through to wait for them."
fi
pending="$(pending_keys "$sid" | paste -sd ' ' -)"
if [[ -z "$agents" ]] && { [[ -n "$pending" ]] || (( ciwatch > 0 )); }; then
  lt="$(cat "$d/rotation-letthrough" 2>/dev/null || true)"
  # No readable turn id (Antigravity): no let-through, it could not be limited to one turn.
  if [[ "$turn" != none ]] && [[ -z "$lt" || "$lt" == "$turn" ]]; then
    echo "$turn" >"$d/rotation-letthrough"
    what="${pending:+pending Next for $pending}"; (( ciwatch > 0 )) && what="${what:+$what, }ci-watch running"
    allow "$head: merge in flight ($what), stop let through once. Finish the merge and its Next message, then rotate (procedure handover.md)."
  fi
fi
max="${COORDINATOR_ROTATE_MAX_BLOCKS:-3}"; [[ "$max" =~ ^[0-9]+$ ]] || max=3
if (( count >= max )); then
  rm -f "$d/rotation-blocks"
  allow "$head; stop allowed after $max blocks. Rotate on the next owner turn."
fi
echo $((count + 1)) >"$d/rotation-blocks"
if [[ -n "$agents" ]]; then
  reason="$head, but background subagent(s) are still running: $agents. Either end the turn now to wait for their reports (the next stop is let through) and rotate after they report, or write them into coordination/handover/coordinator.md as \"running: <agent>, <task>\" and rotate now."
else
  reason="$head."
fi
reason+=" Write coordination/handover/coordinator.md (procedure handover.md, step 3), commit it with bash \"$plugin/scripts/ledger-commit.sh\" <ledger> \"<message>\", then propose the replacement (step 4). Owner on Remote Control (no session can be started): also make the first Owner queue item of COORDINATION.md \"Rotate the coordinator ($(k "$ctx"), past hard): start a fresh session from the handover\" and commit it with the handover."
if (( ag )); then
  printf '{"decision":"continue","reason":%s}\n' "$(json_string "$reason")"
else
  printf '{"decision":"block","reason":%s}\n' "$(json_string "$reason")"
fi
