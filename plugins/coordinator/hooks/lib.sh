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
