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
    printf '%s' "$json" | jq -r --arg f "$field" 'getpath($f | split(".") | map(tonumber? // .)) // "" | tostring' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -I -c '
import json, sys
f = sys.argv[1].split(".")
try:
    v = json.load(sys.stdin)
    for k in f:
        if isinstance(v, dict):
            v = v.get(k)
        elif isinstance(v, list) and k.isdigit() and int(k) < len(v):
            v = v[int(k)]
        else:
            v = None
    if v is None:
        print("")
    elif isinstance(v, (bool, dict, list)):
        print(json.dumps(v))
    else:
        print(v)
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

# is_antigravity <json> -> 0 when the hook input is an Antigravity payload (has conversationId)
is_antigravity() {
  [[ -n "$(json_get "$1" conversationId)" ]]
}

# hook_sid <json> -> session_id (Claude Code) or conversationId (Antigravity)
hook_sid() {
  local s
  s="$(json_get "$1" session_id)"
  [[ -n "$s" ]] || s="$(json_get "$1" conversationId)"
  [[ -n "$s" ]] || return 1
  printf '%s' "$s"
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
#                  "<owner/repo>#<N> <UTC time>" (the key is the first field)
#   stop-blocks    how many times the Stop hook has blocked in the current turn
state_dir() {
  local sid="$1"
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local d="$COORD_HOME/state/$sid"
  mkdir -p "$d" && printf '%s' "$d"
}

# valid_key <owner/repo#N>
valid_key() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]]; }

# pending_add <sid> <owner/repo#N>: record (or refresh) a merged PR waiting for its Next message
pending_add() {
  valid_key "$2" || return 1
  local d f; d="$(state_dir "$1")" || return 1; f="$d/pending-next"
  pending_remove "$1" "$2" || true
  printf '%s %s\n' "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$f"
  rm -f "$d/stop-blocks"
}

# pending_remove <sid> <owner/repo#N>: returns 0 when that PR was pending
pending_remove() {
  local d f; d="$(state_dir "$1")" || return 1; f="$d/pending-next"
  [[ -f "$f" ]] || return 1
  awk -v k="$2" '$1 == k {found=1} END {exit !found}' "$f" || return 1
  awk -v k="$2" '$1 != k' "$f" >"$f.tmp" || true
  mv "$f.tmp" "$f"
  [[ -s "$f" ]] || rm -f "$f" "$d/stop-blocks"
  return 0
}

# pending_keys <sid> [N]: the pending keys, one per line (only those for PR number N if given)
pending_keys() {
  local d; d="$(state_dir "$1")" || return 0
  [[ -f "$d/pending-next" ]] || return 0
  if [[ -n "${2:-}" ]]; then awk -v n="#$2" '{ if (substr($1, length($1) - length(n) + 1) == n) print $1 }' "$d/pending-next"
  else awk '{print $1}' "$d/pending-next"; fi
}

# pending_resolve <sid> <ref>: <ref> is owner/repo#N, #N or N. Prints the one pending key it
# names; returns 1 when none, 2 when a bare number matches PRs in several repos.
pending_resolve() {
  local ref="${2#PR }"; ref="${ref# }"
  if valid_key "$ref"; then
    pending_keys "$1" | grep -qxF "$ref" && { printf '%s' "$ref"; return 0; }
    return 1
  fi
  ref="${ref#\#}"
  [[ "$ref" =~ ^[0-9]+$ ]] || return 1
  local keys n
  keys="$(pending_keys "$1" "$ref")"
  n="$(printf '%s' "$keys" | grep -c . || true)"
  [[ "$n" -eq 0 ]] && return 1
  [[ "$n" -gt 1 ]] && return 2
  printf '%s' "$keys"
}
