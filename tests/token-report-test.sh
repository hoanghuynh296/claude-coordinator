#!/usr/bin/env bash
# token-report.py on a fixture: duplicate streamed messages count once, subagents are named
# from their meta file, tool calls and the largest result are reported.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$root/plugins/coordinator/scripts/token-report.py"
fx="$root/tests/fixtures/token-report/s1.jsonl"
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; }
json="$(python3 -I "$script" "$fx" --json)"
python3 -I - "$json" <<'PY' && ok "json report" || bad "json report"
import json, sys
r = json.loads(sys.argv[1])
s = next(x for x in r if x["name"].startswith("session"))
a = next(x for x in r if "Agent: demo #1" in x["name"])
assert s["calls"] == 2, s            # m1 streamed twice counts once
assert s["cr"] == 3000 and s["cw"] == 500 and s["out"] == 30, s
assert s["tools"] == {"Bash": 1, "Poll": 1}, s["tools"]
assert s["biggest_results"][0]["chars"] == 5000, s["biggest_results"]
assert a["calls"] == 1 and a["cr"] == 300 and "oneoff-builder" in a["name"], a
PY
text="$(python3 -I "$script" "$fx" --top 3)"
grep -q "Agent: demo #1" <<<"$text" && ok "table names the subagent" || bad "table names the subagent"
grep -q "Largest tool results" <<<"$text" && ok "table lists largest results" || bad "table lists largest results"
python3 -I "$script" >/dev/null 2>&1 && bad "no argument exits non-zero" || ok "no argument exits non-zero"
echo "token-report: $pass passed, $failn failed"
[[ $failn -eq 0 ]]
