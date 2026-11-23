#!/usr/bin/env bash
# Check a coordination ledger against the rules a machine can check.
# Usage: ledger-lint.sh [ledger-dir]            (default: current directory)
#
# Errors (exit 1):
#   - a required file is missing (COORDINATION.md, coordination/{README,PROFILE,ROADMAP,DECISIONS}.md)
#   - COORDINATION.md is longer than MAX_LINES (default 80) or has a prose line over MAX_LINE_LEN (240; table rows are exempt)
#   - COORDINATION.md has no "Updated: YYYY-MM-DD" line
#   - a ledger file holds a session id (local_xxxxxxxx) or a home path (/Users/x, /home/x, C:\Users\x)
#   - a decision id (C-123) is cited in the ledger but has no row in DECISIONS.md, or a row id repeats
#     (a reference written <project>:C-123 with a lowercase project name points at another ledger and is allowed)
#   - a decision in DECISIONS.md written as a bullet instead of a table row
#   - a template placeholder ({{NAME}}) is left in a ledger file
# Warnings (exit 0):
#   - "Updated:" is older than STALE_DAYS (default 7), or more than a day older than the last
#     commit that touched COORDINATION.md
#   - COORDINATION.md looks like a log (more than HISTORY_MAX lines that describe finished work)
#   - a "delegat..." line in COORDINATION.md carries no date
#   - PROFILE.md still has unfilled <...> fields
#   - a COORDINATION.md table row that mentions PRs/ahead says "since YYYY-MM-DD" and that date is more than CEILING_DAYS
#     (default 14, the group standard's safety ceiling) ago: the ceiling is passed, so no new
#     feature work in that unit until the open release group is split or finished
#   - a release group heading ("Group <name> → vX.Y.Z") in ROADMAP.md has no "(large)" or "(small)" size;
#     other headings that start with "Group" are ignored
# Release groups are optional: a profile with the old "Integration limit" column and a ROADMAP
# without group headings stay valid (no error, no warning).
#
# Budgets can be set in the environment or in <ledger-dir>/.ledger-lint (KEY=VALUE lines):
#   MAX_LINES, MAX_LINE_LEN, STALE_DAYS, HISTORY_MAX, CEILING_DAYS
set -euo pipefail

dir="${1:-.}"
[[ -d "$dir" ]] || { echo "ledger dir not found: $dir" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ledger-lint.sh needs python3" >&2; exit 2; }

python3 -I - "$dir" "${MAX_LINES:-}" "${MAX_LINE_LEN:-}" "${STALE_DAYS:-}" "${HISTORY_MAX:-}" "${CEILING_DAYS:-}" <<'PY'
import datetime, os, re, subprocess, sys

root = os.path.abspath(sys.argv[1])
cfg = {"MAX_LINES": 80, "MAX_LINE_LEN": 240, "STALE_DAYS": 7, "HISTORY_MAX": 5, "CEILING_DAYS": 14}
rc_file = os.path.join(root, ".ledger-lint")
if os.path.isfile(rc_file):
    with open(rc_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                if k.strip() in cfg and v.strip().isdigit():
                    cfg[k.strip()] = int(v.strip())
for key, arg in zip(("MAX_LINES", "MAX_LINE_LEN", "STALE_DAYS", "HISTORY_MAX", "CEILING_DAYS"), sys.argv[2:7]):
    if arg.isdigit():
        cfg[key] = int(arg)

errors, warnings = [], []
def err(msg): errors.append(msg)
def warn(msg): warnings.append(msg)

def read(rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except FileNotFoundError:
        return None

required = ["COORDINATION.md", "coordination/README.md", "coordination/PROFILE.md",
            "coordination/ROADMAP.md", "coordination/DECISIONS.md"]
for rel in required:
    if read(rel) is None:
        err(f"{rel}: missing (create it with init-ledger.sh)")

# Every ledger file: COORDINATION.md plus everything under coordination/.
files = ["COORDINATION.md"]
coord = os.path.join(root, "coordination")
for base, _dirs, names in os.walk(coord):
    for n in sorted(names):
        if n.endswith(".md"):
            files.append(os.path.relpath(os.path.join(base, n), root))

session_id = re.compile(r"\blocal_[0-9a-f]{8}")
home_path = re.compile(r"(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|[A-Za-z]:\\Users\\[A-Za-z0-9._-]+)")
placeholder = re.compile(r"\{\{[A-Z][A-Z0-9_]*\}\}")
for rel in files:
    lines = read(rel) or []
    for i, line in enumerate(lines, 1):
        if session_id.search(line):
            err(f"{rel}:{i}: session id (sessions are found by name; ids are machine-specific)")
        m = home_path.search(line)
        if m:
            err(f"{rel}:{i}: home path {m.group(1)} (use a path relative to the workspace)")
        if placeholder.search(line):
            err(f"{rel}:{i}: unfilled template placeholder")

ledger = read("COORDINATION.md")
if ledger is not None:
    if len(ledger) > cfg["MAX_LINES"]:
        err(f"COORDINATION.md: {len(ledger)} lines, budget {cfg['MAX_LINES']} "
            "(delete finished items; rules go to PROFILE.md, next work to ROADMAP.md, reasons to DECISIONS.md)")
    for i, line in enumerate(ledger, 1):
        if len(line) > cfg["MAX_LINE_LEN"] and not re.match(r"^\s*\|.*\|\s*$", line):
            err(f"COORDINATION.md:{i}: line of {len(line)} characters, budget {cfg['MAX_LINE_LEN']} (table rows are exempt; shorten the prose)")
    updated = None
    for line in ledger:
        m = re.match(r"\s*Updated:\s*(\d{4}-\d{2}-\d{2})", line)
        if m:
            updated = m.group(1)
            break
    if updated is None:
        err("COORDINATION.md: no 'Updated: YYYY-MM-DD' line")
    else:
        try:
            age = (datetime.date.today() - datetime.date.fromisoformat(updated)).days
            if age > cfg["STALE_DAYS"]:
                warn(f"COORDINATION.md: 'Updated: {updated}' is {age} days old")
            try:
                out = subprocess.run(["git", "-C", root, "log", "-1", "--format=%cs", "--", "COORDINATION.md"],
                                     capture_output=True, text=True, timeout=10).stdout.strip()
                if out:
                    lag = (datetime.date.fromisoformat(out) - datetime.date.fromisoformat(updated)).days
                    if lag > 1:
                        warn(f"COORDINATION.md: 'Updated: {updated}' is {lag} days older than its last commit ({out}); bump it")
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
        except ValueError:
            err(f"COORDINATION.md: 'Updated: {updated}' is not a date")
    history = re.compile(r"\b(merged|released|RELEASED|DONE|done)\b")
    hits = [i for i, line in enumerate(ledger, 1) if history.search(line) and not line.lstrip().startswith("|---")]
    if len(hits) > cfg["HISTORY_MAX"]:
        warn(f"COORDINATION.md: {len(hits)} lines describe finished work (lines {', '.join(map(str, hits[:8]))}...); "
             "the ledger holds live state only")
    today = datetime.date.today()
    for i, line in enumerate(ledger, 1):
        m = re.match(r"\s*\|", line)
        s = re.search(r"since\s+(\d{4}-\d{2}-\d{2})", line) if m and re.search(r"ahead|PRs?\b", line) else None
        if s:
            try:
                age = (today - datetime.date.fromisoformat(s.group(1))).days
                if age > cfg["CEILING_DAYS"]:
                    warn(f"COORDINATION.md:{i}: unit ahead of its release since {s.group(1)} ({age} days, "
                         f"safety ceiling {cfg['CEILING_DAYS']}); split the open group or finish it, then release")
            except ValueError:
                pass
    for i, line in enumerate(ledger, 1):
        if re.search(r"delegat", line, re.I) and not line.lstrip().startswith("#") \
           and not re.search(r"\d{4}-\d{2}-\d{2}", line) and not re.search(r"\bnone\b", line, re.I):
            warn(f"COORDINATION.md:{i}: a delegation without a date")

decisions = read("coordination/DECISIONS.md")
if decisions is not None:
    defined = []
    for line in decisions:
        m = re.match(r"\s*\|\s*(C-\d+)\s*\|", line)
        if m:
            defined.append(m.group(1))
    for i, line in enumerate(decisions, 1):
        if re.match(r"\s*[-*]\s*\**C-\d+", line):
            err(f"coordination/DECISIONS.md:{i}: a decision as a bullet; write a table row: "
                "| C-NNN | YYYY-MM-DD | owner or coordinator | units it binds | the decision |")
    seen = set()
    for d in defined:
        if d in seen:
            err(f"coordination/DECISIONS.md: {d} has more than one row")
        seen.add(d)
    cited = {}
    for rel in files:
        if rel == "coordination/DECISIONS.md":
            continue
        for i, line in enumerate(read(rel) or [], 1):
            # <project>:C-NNN points at another ledger; strip those, then every bare id must exist here
            bare = re.sub(r"(?<![\w.:/-])[a-z0-9][\w.-]*:C-\d+\b", " ", line)
            for d in re.findall(r"(?<![\w-])C-\d+\b", bare):
                cited.setdefault(d, f"{rel}:{i}")
    for d, where in sorted(cited.items()):
        if d not in seen:
            err(f"{where}: {d} is cited but has no row in coordination/DECISIONS.md")

profile = read("coordination/PROFILE.md")
if profile is not None:
    unfilled = [i for i, line in enumerate(profile, 1) if re.search(r"<[a-z][^<>|]*>", line)]
    if unfilled:
        warn(f"coordination/PROFILE.md: {len(unfilled)} lines still have <...> fields to fill")

roadmap = read("coordination/ROADMAP.md")
if roadmap is not None:
    for i, line in enumerate(roadmap, 1):
        if re.match(r"\s*#+\s*Group\s+\S.*(→|->)\s*v?\d", line) and not re.search(r"\((large|small)\)", line):
            warn(f"coordination/ROADMAP.md:{i}: a release group heading needs its size: "
                 "Group <name> → vX.Y.Z (large|small)")

for w in warnings:
    print(f"warning: {w}")
for e in errors:
    print(f"error: {e}")
print(f"ledger-lint: {len(errors)} error(s), {len(warnings)} warning(s)")
sys.exit(1 if errors else 0)
PY
