#!/usr/bin/env bash
# scripts/ci-watch.sh against a fake gh: green, red, stale head, moved head, pending -> green,
# no checks, timeout, not open, gh errors, bad arguments.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$root/plugins/coordinator/scripts/ci-watch.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; }

# Fake gh: `pr view` prints $F/view; `pr checks` prints the next of $F/checks.1, .2, ... (the
# last one repeats); a file content "ERR <text>" exits 1 with <text> on stderr.
cat >"$tmp/gh" <<'GH'
#!/usr/bin/env bash
F="$FAKE"
out() { local c; c="$(cat "$1")"; if [[ "$c" == ERR* ]]; then echo "${c#ERR }" >&2; exit 1; fi; printf '%s\n' "$c"; }
case "$1 $2" in
  "pr view") n=$(cat "$F/vn" 2>/dev/null || echo 0); n=$((n+1)); echo $n >"$F/vn"
             [[ -f "$F/view.$n" ]] && out "$F/view.$n" || out "$F/view" ;;
  "pr checks") n=$(cat "$F/n" 2>/dev/null || echo 0); n=$((n+1)); echo $n >"$F/n"
               [[ -f "$F/checks.$n" ]] && out "$F/checks.$n" || out "$(ls "$F"/checks.* | sort -t. -k2 -n | tail -1)" ;;
esac
GH
chmod +x "$tmp/gh"
export COORDINATOR_GH="$tmp/gh" CI_WATCH_INTERVAL=0 CI_WATCH_DEADLINE=5 CI_WATCH_NOCHECKS=5
SHA=abcdef1234567890abcdef1234567890abcdef12
case_() { rm -rf "$tmp/f"; mkdir -p "$tmp/f"; export FAKE="$tmp/f"
  printf '{"state":"OPEN","headRefOid":"%s"}' "$SHA" >"$FAKE/view"; }
expect() { # name code needle -- args
  local name="$1" code="$2" needle="$3"; shift 4
  local o rc; o="$(bash "$script" "$@" 2>&1)"; rc=$?
  if [[ $rc -eq $code && "$o" == *"$needle"* ]]; then ok "$name"; else bad "$name (rc $rc: $o)"; fi; }
P='{"name":"%s","bucket":"%s","link":"https://ci/%s"}'
checks() { local i="$1"; shift; local s="[" sep=""; while [[ $# -gt 0 ]]; do s+="$sep$(printf "$P" "$1" "$2" "$1")"; sep=","; shift 2; done; echo "$s]" >"$FAKE/checks.$i"; }

case_; checks 1 lint pass test pass
expect "all checks pass -> green" 0 "o/r#7 abcdef1 green (2 checks" -- o/r 7 abcdef1
case_; checks 1 lint pending test pending; checks 2 lint pass test pending; checks 3 lint pass test skipping
expect "pending, then pass/skipping -> green" 0 "green (2 checks" -- o/r 7 "$SHA"
case_; checks 1 lint fail test pending
expect "first failure -> red at once, names the check" 1 "red: lint (1 still pending) https://ci/lint" -- o/r 7
case_; checks 1 lint cancel
expect "cancelled -> red" 1 "red: lint" -- o/r 7
case_; checks 1 lint pass
expect "reported sha is not the head -> stale-head" 3 "stale-head: head is abcdef1, reported 1234567" -- o/r 7 1234567
case_; checks 1 lint pending; printf '{"state":"OPEN","headRefOid":"9999999aaaa"}' >"$FAKE/view.2"; printf '{"state":"OPEN","headRefOid":"9999999aaaa"}' >"$FAKE/view.3"
expect "head moves while watching -> stale-head" 3 "stale-head: head is 9999999" -- o/r 7 abcdef1
case_; echo "ERR no checks reported on the 'x' branch" >"$FAKE/checks.1"; checks 2 ci pass
expect "no checks yet (queued runner), then green" 0 "green (1 checks" -- o/r 7
case_; echo "ERR no checks reported on the 'x' branch" >"$FAKE/checks.1"
CI_WATCH_INTERVAL=0.2 CI_WATCH_NOCHECKS=0.5 expect "never any check -> no-checks" 5 "no-checks after" -- o/r 7
case_; checks 1 lint pending
CI_WATCH_INTERVAL=0.2 CI_WATCH_DEADLINE=0.5 expect "still pending at the deadline -> timeout" 4 "timeout after 0m: pending lint" -- o/r 7
case_; printf '{"state":"MERGED","headRefOid":"%s"}' "$SHA" >"$FAKE/view"; checks 1 lint pass
expect "merged PR -> not open" 6 "merged (not open)" -- o/r 7
case_; echo "ERR HTTP 404: Not Found" >"$FAKE/view"; checks 1 lint pass
expect "gh fails three times -> error" 2 "error: HTTP 404: Not Found" -- o/r 7
case_; echo "ERR rate limit" >"$FAKE/checks.1"; checks 2 lint pass
expect "one gh hiccup is retried" 0 "green" -- o/r 7
expect "bad repo argument -> usage" 2 "Usage" -- notarepo 7
expect "bad sha argument -> usage" 2 "Usage" -- o/r 7 xyz
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
