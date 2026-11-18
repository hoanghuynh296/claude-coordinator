#!/usr/bin/env bash
# UserPromptSubmit hook, and PostToolUse hook for the inbox tools (ReadNotifications,
# FetchInboxMessage). When a registered coordinator receives a text that says "PR ready", it is
# reminded to start the background CI watch in this turn (review-merge.md, step 2): agents
# report on push, and a green CI run wakes nobody, so the watch's exit is what brings the
# coordinator back when CI ends. A reminder only, never a block: how an agent's message reaches
# the coordinator depends on the host, so the procedure is the rule and this hook a nudge.
# PR links (github.com/<owner>/<repo>/pull/<N>) in the text become ready-to-run commands.
# Unregistered sessions and other texts: no output.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

event="$(json_get "$input" hook_event_name)"
if [[ "$event" == "UserPromptSubmit" ]]; then
  text="$(json_get "$input" prompt)"
else
  event="PostToolUse"
  text="$(json_get "$input" tool_response)"
fi
# Only a report counts: a message whose FIRST line starts with "PR ready" (any case). The phrase
# later in the text, in a quote or in a progress note does not (agents' format: unit-brief.md).
# Inbox results hold several messages (JSON): any one of them may qualify; a message starts at the
# top, or at a <cross-session-message ...> wrapper tag (inline or alone on its line), and leading
# blank lines are skipped. A user prompt that quotes a wrapper block with "PR ready" right after
# the tag still fires: accepted.
firsts="$(printf '%s' "$text" | python3 -I -c '
import json, re, sys
raw = sys.stdin.read()
def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, dict):
        for x in v.values(): yield from strings(x)
    elif isinstance(v, list):
        for x in v: yield from strings(x)
try:
    items = list(strings(json.loads(raw)))
except ValueError:
    items = [raw]
head = re.compile(r"PR\s+(is\s+)?ready\b", re.I)
wrap = re.compile(r"<\\?cross-session-message[^>]*>")
for t in items:
    at_start, hit = True, False
    for line in t.split("\n"):
        l = line.strip()
        m = wrap.match(l)
        if m:                       # a wrapper tag opens a new message, inline or on its own line
            l, at_start = l[m.end():].strip(), True
        if not at_start or not l:
            continue
        hit = hit or bool(head.match(l)); at_start = False
    if hit:
        print(t)
' 2>/dev/null)"
[[ -n "$firsts" ]] || exit 0
text="$firsts"

cmds=(); rest="$text"
re='github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)(.*)'
while [[ "$rest" =~ $re ]]; do
  c="bash \"$plugin/scripts/ci-watch.sh\" ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} <head sha>"
  rest="${BASH_REMATCH[3]}"
  [[ " ${cmds[*]-} " == *"$c"* ]] || cmds+=("$c")
done

msg="Coordinator: an agent reported \"PR ready\". In THIS turn start the CI watch in the background (Bash with run_in_background), with the head SHA from the report: bash \"$plugin/scripts/ci-watch.sh\" <owner/repo> <N> <head sha>. Its exit wakes you when CI ends (green, red or stale-head); a green run wakes nobody else. Review in parallel (Reviewer if the profile requires it); merge only when CI is green on the reported head and the review passed (review-merge.md, steps 2 and 6)."
[[ ${#cmds[@]} -gt 0 ]] && msg+=" For the PR(s) named: $(printf '%s; ' "${cmds[@]}")"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$event" "$(json_string "${msg%; }")"
