#!/usr/bin/env bash
# Print the current context size of Claude sessions on this machine, from their transcripts.
# Usage: check-context.sh [--soft N] [--hard N] [--window N] <session_id|transcript.jsonl>...
#        (no sessions: the 10 most recent). N is tokens; a k or m suffix is allowed (250k, 1m).
# Context = input + cache_read + cache_creation tokens of the last assistant turn.
# One line per session: "<session>  <size>k  <level>  <title>", level is
#   ok    under the soft threshold
#   SOFT  at or above soft (default 250k): finish the current issue, take no new one, then rotate
#   HARD  at or above hard (default 400k, capped at 75% of --window): stop at the next safe
#         point, write the handover, report "blocked: rotate"
# Thresholds also come from SOFT_AT, HARD_AT and CONTEXT_WINDOW (ROTATE_AT is the old name of
# SOFT_AT); arguments win over the environment.
set -euo pipefail

usage() { sed -n '3,4p' "$0" | sed 's/^# //' >&2; exit 2; }
soft="${SOFT_AT:-${ROTATE_AT:-250k}}"
hard="${HARD_AT:-400k}"
window="${CONTEXT_WINDOW:-}"
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
command -v python3 >/dev/null 2>&1 || { echo "check-context.sh needs python3" >&2; exit 1; }

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --soft) [[ $# -ge 2 ]] || usage; soft="$2"; shift 2 ;;
    --hard) [[ $# -ge 2 ]] || usage; hard="$2"; shift 2 ;;
    --window) [[ $# -ge 2 ]] || usage; window="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown option $1" >&2; usage ;;
    *) args+=("$1"); shift ;;
  esac
done

files=()
if [[ ${#args[@]} -eq 0 ]]; then
  # shellcheck disable=SC2012  # ls -t is the portable way to sort by mtime; names are UUIDs
  while IFS= read -r f; do files+=("$f"); done < <(ls -t "$projects"/*/*.jsonl 2>/dev/null | head -n 10)
else
  for a in "${args[@]}"; do
    if [[ -f "$a" ]]; then files+=("$a")
    else
      matches=("$projects"/*/"$a".jsonl)
      if [[ -f "${matches[0]}" ]]; then files+=("${matches[0]}"); else echo "no transcript for $a" >&2; fi
    fi
  done
fi
[[ ${#files[@]} -gt 0 ]] || { echo "no transcripts found" >&2; exit 1; }

python3 -I - "$soft" "$hard" "$window" "${files[@]}" <<'PY'
import json, os, sys

def tokens(text):
    t = text.strip().lower()
    mult = {"k": 1000, "m": 1000000}.get(t[-1:], 1)
    if mult != 1:
        t = t[:-1]
    try:
        n = int(float(t) * mult)
    except ValueError:
        sys.exit(f"check-context.sh: not a token count: {text!r}")
    if n <= 0:
        sys.exit(f"check-context.sh: threshold must be positive: {text!r}")
    return n

soft, hard = tokens(sys.argv[1]), tokens(sys.argv[2])
if sys.argv[3]:
    hard = min(hard, tokens(sys.argv[3]) * 3 // 4)
if hard < soft:
    sys.exit(f"check-context.sh: hard threshold {hard} is below soft {soft}")
for path in sys.argv[4:]:
    last, title = None, ""
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") in ("custom-title", "summary") and (rec.get("customTitle") or rec.get("summary")):
                title = rec.get("customTitle") or rec.get("summary")
            msg = rec.get("message") or {}
            u = msg.get("usage") if isinstance(msg, dict) else None
            if rec.get("type") == "assistant" and u and not rec.get("isSidechain"):
                last = u
    sid = os.path.basename(path)[:-6]
    if last is None:
        print(f"{sid}  no usage yet  {title}")
        continue
    ctx = last.get("input_tokens", 0) + last.get("cache_read_input_tokens", 0) + last.get("cache_creation_input_tokens", 0)
    level = "HARD" if ctx >= hard else "SOFT" if ctx >= soft else "ok"
    print(f"{sid}  {ctx // 1000:>4}k  {level:<4}  {title}")
PY
