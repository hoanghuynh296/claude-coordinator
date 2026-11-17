#!/usr/bin/env bash
# Watch a PR's CI until it ends and print one summary line. The coordinator runs it in the
# background (Bash with run_in_background) in the same turn as every "PR ready": the command's
# exit is what wakes the coordinator when CI ends, since a green run wakes nobody else.
#
# Usage: ci-watch.sh <owner/repo> <N> [<sha>]
#   <sha>  the head the agent reported (full or a prefix of 7+). When the PR's head is or
#          becomes another commit, the watch stops with "stale-head": review the new report.
#
# It polls `gh pr checks <N> --json name,bucket,link` (what `gh pr checks --watch` shows, but it
# also catches a moved head, a PR with no checks yet while a runner is queued, and a deadline).
# Last line, and exit code:
#   ci-watch: <repo>#<N> <sha7> green (<k> checks, <m>m)                0
#   ci-watch: <repo>#<N> <sha7> red: <failed checks> <first link>       1  (at the first failure)
#   ci-watch: <repo>#<N> error: <what gh said>                          2
#   ci-watch: <repo>#<N> stale-head: head is <sha7>, reported <sha7>    3
#   ci-watch: <repo>#<N> <sha7> timeout after <m>m: pending <checks>    4
#   ci-watch: <repo>#<N> <sha7> no-checks after <m>m                    5
#   ci-watch: <repo>#<N> <state> (not open)                              6
# Environment: CI_WATCH_DEADLINE (seconds, default 5400), CI_WATCH_INTERVAL (default 30),
# CI_WATCH_NOCHECKS (seconds to wait for a first check, default 900), COORDINATOR_GH (gh binary).
# Needs python3.
set -euo pipefail

usage() { sed -n '6,8p' "$0" | sed 's/^# //' >&2; exit 2; }
repo="${1:-}"; num="${2:-}"; sha="${3:-}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$num" =~ ^[0-9]+$ ]] || usage
[[ -z "$sha" || "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || usage
command -v python3 >/dev/null 2>&1 || { echo "ci-watch: $repo#$num error: python3 missing"; exit 2; }

exec python3 -I - "${COORDINATOR_GH:-gh}" "$repo" "$num" "$sha" \
  "${CI_WATCH_DEADLINE:-5400}" "${CI_WATCH_INTERVAL:-30}" "${CI_WATCH_NOCHECKS:-900}" <<'PY'
import json, subprocess, sys, time
gh, repo, num, want, deadline, interval, nochecks = sys.argv[1:8]
deadline, interval, nochecks = float(deadline), float(interval), float(nochecks)
want = want.lower()
ref = f"{repo}#{num}"
start = time.monotonic()

def mins():
    return f"{int((time.monotonic() - start) // 60)}m"

def done(code, text):
    print(f"ci-watch: {ref} {text}", flush=True)
    sys.exit(code)

def run(args):
    try:
        p = subprocess.run([gh, *args], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    return p, (p.stderr or p.stdout).strip()

errors = 0
while True:
    p, msg = run(["pr", "view", num, "--repo", repo, "--json", "state,headRefOid"])
    try:
        pr = json.loads(p.stdout) if p and p.returncode == 0 else None
    except ValueError:
        pr = None
    if pr is None:
        errors += 1
        if errors >= 3:
            done(2, f"error: {msg.splitlines()[-1] if msg else 'gh pr view failed'}")
    else:
        errors = 0
        head = (pr.get("headRefOid") or "").lower()
        if pr.get("state") != "OPEN":
            done(6, f"{pr.get('state', '?').lower()} (not open)")
        if want and not head.startswith(want):
            done(3, f"stale-head: head is {head[:7]}, reported {want[:7]}")
        p, msg = run(["pr", "checks", num, "--repo", repo, "--json", "name,bucket,link"])
        checks = None
        if p is not None and p.stdout.strip():
            try:
                checks = json.loads(p.stdout)
            except ValueError:
                checks = None
        if checks is None and "no checks reported" in msg:
            checks = []
        if checks is None:
            errors += 1
            if errors >= 3:
                done(2, f"error: {msg.splitlines()[-1] if msg else 'gh pr checks failed'}")
        else:
            pending = [c["name"] for c in checks if c.get("bucket") == "pending"]
            failed = [c for c in checks if c.get("bucket") in ("fail", "cancel")]
            if failed:  # a failed check is final: report it without waiting for the rest
                names = ", ".join(c["name"] for c in failed)
                more = f" ({len(pending)} still pending)" if pending else ""
                done(1, f"{head[:7]} red: {names}{more} {failed[0].get('link', '')}".rstrip())
            if checks and not pending:
                done(0, f"{head[:7]} green ({len(checks)} checks, {mins()})")
            if not checks and time.monotonic() - start >= nochecks:
                done(5, f"{head[:7]} no-checks after {mins()}")
            if time.monotonic() - start >= deadline:
                done(4, f"{head[:7]} timeout after {mins()}: pending {', '.join(pending) or '-'}")
    time.sleep(interval)
PY
