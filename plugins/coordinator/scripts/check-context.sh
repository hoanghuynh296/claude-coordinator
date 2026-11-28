#!/usr/bin/env bash
# Print the current context size of Claude sessions on this machine, from their transcripts.
# Usage: check-context.sh [--role coordinator|agent] [--coordinator] [--profile PROFILE.md|ledger]
#          [--soft N] [--hard N] [--window N] <session_id|transcript.jsonl>...
#        (no sessions: the 10 most recent). N is tokens; a k or m suffix is allowed (250k, 1m).
# Context = input + cache_read + cache_creation tokens of the last assistant turn.
# One line per session: "<session>  <size>k / <soft|hard> <threshold>k: <level>  <title>", level is
#   ok    under the soft threshold
#   SOFT  at or above soft: finish the current issue, take no new one, then rotate
#   HARD  at or above hard: stop at the next safe point, write the handover,
#         report "blocked: rotate"
# The line names the threshold it was measured against: soft for ok and SOFT, hard for HARD.
# Role: a session titled "Coordinator: ..." is a coordinator, any other an agent; --role (or
# --coordinator, the same as --role coordinator) sets it for every session listed.
# Thresholds per role, later wins:
#   1. kit defaults: agent soft 250k, hard 400k; coordinator soft 300k, hard 450k (C-015)
#   2. --profile: the "Budgets" section of the ledger's PROFILE.md (a ledger folder means its
#      coordination/PROFILE.md); a value it does not give keeps the default
#   3. SOFT_AT, HARD_AT (ROTATE_AT is the old name of SOFT_AT): agents only
#   4. --soft, --hard: every session listed
# --window (or CONTEXT_WINDOW) then caps soft at 50% and hard at 75% of the model's context
# window (a 200k window gives soft 100k, hard 150k). One window applies to every session
# listed: run once per model group.
set -euo pipefail

usage() { sed -n '3,5p' "$0" | sed 's/^# //' >&2; exit 2; }
env_soft="${SOFT_AT:-${ROTATE_AT:-}}"
env_hard="${HARD_AT:-}"
window="${CONTEXT_WINDOW:-}"
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
ag_brains="${ANTIGRAVITY_BRAIN_DIR:-$HOME/.gemini/antigravity/brain}"
command -v python3 >/dev/null 2>&1 || { echo "check-context.sh needs python3" >&2; exit 1; }

args=(); soft_arg=""; hard_arg=""; role="auto"; profile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --soft) [[ $# -ge 2 ]] || usage; soft_arg="$2"; shift 2 ;;
    --hard) [[ $# -ge 2 ]] || usage; hard_arg="$2"; shift 2 ;;
    --role) [[ $# -ge 2 ]] || usage
      case "$2" in coordinator|agent|auto) role="$2" ;; *) echo "unknown role $2 (coordinator, agent)" >&2; usage ;; esac
      shift 2 ;;
    --coordinator) role=coordinator; shift ;;
    --profile) [[ $# -ge 2 ]] || usage; profile="$2"; shift 2 ;;
    --window) [[ $# -ge 2 ]] || usage; window="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown option $1" >&2; usage ;;
    *) args+=("$1"); shift ;;
  esac
done
if [[ -n "$profile" ]]; then
  if [[ -d "$profile" ]]; then
    if [[ -f "$profile/coordination/PROFILE.md" ]]; then profile="$profile/coordination/PROFILE.md"
    elif [[ -f "$profile/PROFILE.md" ]]; then profile="$profile/PROFILE.md"
    else echo "no PROFILE.md in $profile" >&2; exit 1; fi
  elif [[ ! -f "$profile" ]]; then echo "no profile at $profile" >&2; exit 1; fi
fi

files=()
if [[ ${#args[@]} -eq 0 ]]; then
  # shellcheck disable=SC2012  # ls -t is the portable way to sort by mtime; names are UUIDs
  while IFS= read -r f; do files+=("$f"); done < <(ls -t "$projects"/*/*.jsonl "$ag_brains"/*/.system_generated/logs/transcript.jsonl 2>/dev/null | head -n 10)
else
  for a in "${args[@]}"; do
    if [[ -f "$a" ]]; then files+=("$a")
    elif [[ -f "$ag_brains/$a/.system_generated/logs/transcript.jsonl" ]]; then
      files+=("$ag_brains/$a/.system_generated/logs/transcript.jsonl")
    else
      matches=("$projects"/*/"$a".jsonl)
      if [[ -f "${matches[0]}" ]]; then files+=("${matches[0]}"); else echo "no transcript for $a" >&2; fi
    fi
  done
fi
[[ ${#files[@]} -gt 0 ]] || { echo "no transcripts found" >&2; exit 1; }

python3 -I - "$role" "$profile" "$env_soft" "$env_hard" "$soft_arg" "$hard_arg" "$window" "${files[@]}" <<'PY'
import json, os, re, sys

def tokens(text):
    t = text.strip().lower()
    mult = {"k": 1000, "m": 1000000}.get(t[-1:], 1)
    if mult != 1:
        t = t[:-1]
    try:
        n = int(float(t) * mult)
    except (ValueError, OverflowError):
        sys.exit(f"check-context.sh: not a token count: {text!r}")
    if n <= 0:
        sys.exit(f"check-context.sh: threshold must be positive: {text!r}")
    return n

def profile_budgets(path):
    """Soft and hard thresholds per role from the Budgets section of a PROFILE.md.

    Ledgers word it many ways ("Context, soft: 250k. Hard: 400k. Coordinator: soft 300k, hard
    450k", "Context, soft: agents 250k, coordinator 300k", "The coordinator's are soft 300k,
    hard 450k"), so each bullet is read left to right: a role word (coordinator, agent) sets
    the role (agent at the start of a bullet), a level word (soft, hard) sets the level (a
    sentence end clears it), and a count with a k or m suffix is that role's level. The first
    value found for a role and level wins; a count with no level is ignored.
    """
    found = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    section, depth = [], None
    for line in text.splitlines():
        h = re.match(r"^(#+)\s+(.*)", line)
        if h:
            if depth is not None and len(h.group(1)) <= depth:
                break
            if depth is None and re.search(r"\bbudgets?\b", h.group(2), re.I):
                depth = len(h.group(1))
            continue
        if depth is not None:
            section.append(line)
    bullets, cur = [], ""
    for line in section:
        if re.match(r"^\s*[-*]\s", line):
            bullets.append(cur)
            cur = re.sub(r"^\s*[-*]\s", "", line)
        else:
            cur += " " + line.strip()
    bullets.append(cur)
    word = re.compile(r"(?P<role_c>\bcoordinators?(?:'s)?\b)|(?P<role_a>\bagents?(?:'s)?\b)"
                      r"|(?P<soft>\bsoft\b)|(?P<hard>\bhard\b)|(?P<stop>\.(?:\s|$))"
                      r"|(?P<n>\b\d+(?:\.\d+)?\s*[km]\b)", re.I)
    for b in bullets:
        role, level = "agent", None
        for m in word.finditer(b.replace("<", " ").replace(">", " ")):
            kind = m.lastgroup
            if kind == "role_c":
                role = "coordinator"
            elif kind == "role_a":
                role = "agent"
            elif kind in ("soft", "hard"):
                level = kind
            elif kind == "stop":
                level = None
            elif level:
                found.setdefault((role, level), tokens(m.group(0).replace(" ", "")))
    return found

role_arg, profile, env_soft, env_hard, soft_arg, hard_arg, window_arg = sys.argv[1:8]
limits = {"agent": {"soft": 250000, "hard": 400000},
          "coordinator": {"soft": 300000, "hard": 450000}}
if profile:
    for (r, lv), n in profile_budgets(profile).items():
        limits[r][lv] = n
if env_soft:
    limits["agent"]["soft"] = tokens(env_soft)
if env_hard:
    limits["agent"]["hard"] = tokens(env_hard)
for r in limits:
    if soft_arg:
        limits[r]["soft"] = tokens(soft_arg)
    if hard_arg:
        limits[r]["hard"] = tokens(hard_arg)
    if window_arg:
        window = tokens(window_arg)
        limits[r]["soft"] = min(limits[r]["soft"], window // 2)
        limits[r]["hard"] = min(limits[r]["hard"], window * 3 // 4)

def k(n):
    return f"{n // 1000}k" if n % 1000 == 0 or n >= 10000 else f"{n / 1000:g}k"

rows = []
for path in sys.argv[8:]:
    last, title, custom = None, "", ""
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") in ("custom-title", "summary") and (rec.get("customTitle") or rec.get("summary")):
                title = rec.get("customTitle") or rec.get("summary")
                if rec.get("customTitle"):
                    custom = rec["customTitle"]
            msg = rec.get("message") or {}
            u = msg.get("usage") if isinstance(msg, dict) else None
            if rec.get("type") == "assistant" and u and not rec.get("isSidechain"):
                last = u
            elif rec.get("type") == "PLANNER_RESPONSE" and ("input_tokens" in rec or "cache_read_tokens" in rec):
                last = {
                    "input_tokens": rec.get("input_tokens", 0),
                    "cache_read_input_tokens": rec.get("cache_read_tokens", 0),
                    "cache_creation_input_tokens": rec.get("cache_creation_tokens", 0),
                }
    base = os.path.basename(path)
    if base == "transcript.jsonl" and os.path.basename(os.path.dirname(path)) == "logs":
        sid = os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(path))))
    else:
        sid = base[:-6]
    role = role_arg if role_arg != "auto" else (
        "coordinator" if re.match(r"\s*Coordinator\s*:", custom) else "agent")
    rows.append((sid, last, role, title))

for r in sorted({row[2] for row in rows if row[1] is not None}):
    if limits[r]["hard"] < limits[r]["soft"]:
        sys.exit(f"check-context.sh: {r} hard threshold {limits[r]['hard']} is below soft {limits[r]['soft']}")
for sid, last, role, title in rows:
    if last is None:
        print(f"{sid}  no usage yet  {title}")
        continue
    ctx = last.get("input_tokens", 0) + last.get("cache_read_input_tokens", 0) + last.get("cache_creation_input_tokens", 0)
    soft, hard = limits[role]["soft"], limits[role]["hard"]
    if ctx >= hard:
        level, used = "HARD", f"hard {k(hard)}"
    else:
        level, used = ("SOFT" if ctx >= soft else "ok"), f"soft {k(soft)}"
    print(f"{sid}  {ctx // 1000:>4}k / {used}: {level:<4}  {title}")
PY
