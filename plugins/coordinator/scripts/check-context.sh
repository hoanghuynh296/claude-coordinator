#!/usr/bin/env bash
# Print the current context size of Claude sessions on this machine, from their transcripts.
# Usage: check-context.sh <session_id|transcript.jsonl>...   (no args: 10 most recent sessions)
# Context = input + cache_read + cache_creation tokens of the last assistant turn.
# Flags sessions at or above ${ROTATE_AT:-250000} tokens.
set -euo pipefail

rotate_at="${ROTATE_AT:-250000}"
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
command -v python3 >/dev/null 2>&1 || { echo "check-context.sh needs python3" >&2; exit 1; }

files=()
if [[ $# -eq 0 ]]; then
  # shellcheck disable=SC2012  # ls -t is the portable way to sort by mtime; names are UUIDs
  while IFS= read -r f; do files+=("$f"); done < <(ls -t "$projects"/*/*.jsonl 2>/dev/null | head -n 10)
else
  for a in "$@"; do
    if [[ -f "$a" ]]; then files+=("$a")
    else
      matches=("$projects"/*/"$a".jsonl)
      if [[ -f "${matches[0]}" ]]; then files+=("${matches[0]}"); else echo "no transcript for $a" >&2; fi
    fi
  done
fi
[[ ${#files[@]} -gt 0 ]] || { echo "no transcripts found" >&2; exit 1; }

python3 -I - "$rotate_at" "${files[@]}" <<'PY'
import json, os, sys
limit = int(sys.argv[1])
for path in sys.argv[2:]:
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
    flag = "ROTATE" if ctx >= limit else "ok"
    print(f"{sid}  {ctx // 1000:>4}k  {flag:<6}  {title}")
PY
