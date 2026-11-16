#!/usr/bin/env bash
# Shared helpers for the coordinator hooks. Uses jq when present, else python3.
# Registration files live in ${COORDINATOR_HOME:-$HOME/.claude/coordinator}/sessions/<session_id>
# and hold key=value lines: ledger=<abs dir>, project=<abs dir>, registered=<date>.

COORD_HOME="${COORDINATOR_HOME:-$HOME/.claude/coordinator}"

# have_jq: jq available and not disabled (COORDINATOR_NO_JQ=1 forces the python3 path, for tests)
have_jq() { [[ -z "${COORDINATOR_NO_JQ:-}" ]] && command -v jq >/dev/null 2>&1; }

# json_get <json> <field>  -> prints a top-level or dotted field ("" when missing)
json_get() {
  local json="$1" field="$2"
  if have_jq; then
    printf '%s' "$json" | jq -r --arg f "$field" 'getpath($f | split(".")) // "" | tostring' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -I -c '
import json, sys
f = sys.argv[1].split(".")
try:
    v = json.load(sys.stdin)
    for k in f:
        v = v.get(k) if isinstance(v, dict) else None
    print("" if v is None else v)
except Exception:
    print("")
' "$field"
  else
    echo "coordinator hook: needs jq or python3" >&2
    return 1
  fi
}

# json_string <text> -> JSON string literal
json_string() {
  if have_jq; then
    printf '%s' "$1" | jq -Rs .
  else
    printf '%s' "$1" | python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  fi
}

# registration_file <session_id> -> path if the session is a registered coordinator
registration_file() {
  local sid="$1"
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local f="$COORD_HOME/sessions/$sid"
  [[ -f "$f" ]] || return 1
  printf '%s' "$f"
}

# reg_value <file> <key>
reg_value() {
  sed -n "s/^$2=//p" "$1" | head -n 1
}

# reg_values <file> <key> -> every value of a repeated key, one per line
reg_values() {
  sed -n "s/^$2=//p" "$1"
}

# Per-session hook state of a registered coordinator: $COORD_HOME/state/<session_id>/
#   pending-next   one line per merged PR still waiting for "PR #N merged. Next: ..":
#                  "<N> <repo or -> <UTC time>"
#   stop-blocks    how many times the Stop hook has blocked in the current turn
state_dir() {
  local sid="$1"
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local d="$COORD_HOME/state/$sid"
  mkdir -p "$d" && printf '%s' "$d"
}

# pending_add <sid> <pr> <repo>: record (or refresh) PR <pr> as waiting for its Next message
pending_add() {
  local d f; d="$(state_dir "$1")" || return 1; f="$d/pending-next"
  pending_remove "$1" "$2"
  printf '%s %s %s\n' "$2" "${3:--}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$f"
  rm -f "$d/stop-blocks"
}

# pending_remove <sid> <pr>: returns 0 when the PR was pending
pending_remove() {
  local d f; d="$(state_dir "$1")" || return 1; f="$d/pending-next"
  [[ -f "$f" ]] || return 1
  grep -q "^$2 " "$f" || return 1
  grep -v "^$2 " "$f" >"$f.tmp" || true
  mv "$f.tmp" "$f"
  [[ -s "$f" ]] || rm -f "$f" "$d/stop-blocks"
  return 0
}

# pending_list <sid>: the pending PR lines (nothing when none)
pending_list() {
  local d; d="$(state_dir "$1")" || return 0
  [[ -f "$d/pending-next" ]] && cat "$d/pending-next"
  return 0
}
