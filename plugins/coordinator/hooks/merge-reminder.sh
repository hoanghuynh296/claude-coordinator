#!/usr/bin/env bash
# PostToolUse hook for Bash. After a registered coordinator merges a PR with `gh pr merge <N>`:
#   - records owner/repo#N as "pending Next" in the session's state dir (lib.sh, state_dir);
#     the Stop hook (next-guard.sh) blocks the end of the turn until the author got
#     "PR #N merged. Next: ..." (cleared by next-sent.sh) or the coordinator cleared it with
#     scripts/next-clear.sh;
#   - reminds it to send that message and to archive a per-issue agent's session.
# The command is split like a shell would (python shlex): only `gh pr merge` at the start of a
# command counts (not `echo gh pr merge 9`), quoted flag values are skipped. Whether the merge
# happened is not guessed from the output (a `; echo ok` or `|| true` hides a failure): each PR
# is looked up with `gh pr view` and recorded only when its state is MERGED. When gh cannot
# answer, nothing is recorded and the reminder is shown anyway (fail open).
# Unregistered sessions and other commands: no output, no state. Needs python3 to record.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
registration_file "$sid" >/dev/null || exit 0

cmd="$(json_get "$input" tool_input.command)"
[[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+merge ]] || exit 0
[[ "$(json_get "$input" tool_response.interrupted)" == "true" ]] && exit 0
cwd="$(json_get "$input" cwd)"

generic="Coordinator: a PR may have been merged. If so, send its author \"PR #<N> merged. Next: <issue | handover | stand by | done>\" in this turn (review-merge.md, step 9); for a per-issue agent, archive its session afterwards (mcp__ccd_session_mgmt__archive_session); a standing session is archived only on rotation."
emit() { printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$1")"; }

if ! command -v python3 >/dev/null 2>&1; then emit "$generic (python3 missing: the merge was not recorded.)"; exit 0; fi

# One line per finding: MERGED <repo#N> | OPEN <ref> <state> | ERROR <ref> | AUTO <ref> | UNPARSED
result="$(python3 -I - "${COORDINATOR_GH:-gh}" "${cwd:-$PWD}" "$cmd" <<'PY'
import json, os, re, shlex, subprocess, sys
gh, cwd = sys.argv[1], sys.argv[2]
cmd = sys.argv[3].replace("\n", " ; ")
try:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    toks = cmd.split()
seps = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
with_value = {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email",
              "--match-head-commit"}
merges, i, start = [], 0, True
while i < len(toks):
    t = toks[i]
    if t in seps:
        start = True; i += 1; continue
    if start and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):   # VAR=value prefix
        i += 1; continue
    if start and t in ("sudo", "command", "exec", "time"):
        i += 1; continue
    if start and t == "gh" and toks[i+1:i+3] == ["pr", "merge"]:
        j, pr, repo, auto = i + 3, None, None, False
        while j < len(toks) and toks[j] not in seps:
            a = toks[j]
            if a in ("-R", "--repo") and j + 1 < len(toks):
                repo = toks[j+1]; j += 2; continue
            if a.startswith("--repo="):
                repo = a.split("=", 1)[1]
            elif a in with_value:
                j += 2; continue
            elif a == "--auto":
                auto = True
            elif not a.startswith("-") and pr is None:
                pr = a
            j += 1
        merges.append((pr, repo, auto))
        i = j; start = False; continue
    start = False; i += 1
for pr, repo, auto in merges:
    m = re.match(r"^#?(\d+)$", pr or "")
    u = re.match(r"^https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", pr or "")
    if u:
        repo, num = repo or u.group(1), u.group(2)
    elif m:
        num = m.group(1)
    else:
        print("UNPARSED"); continue
    ref = (repo + "#" + num) if repo else ("#" + num)
    if auto:
        print("AUTO", ref); continue
    args = [gh, "pr", "view", num, "--json", "state,url"] + (["-R", repo] if repo else [])
    try:
        r = subprocess.run(args, cwd=cwd if os.path.isdir(cwd) else None, capture_output=True,
                           text=True, timeout=10)
        data = json.loads(r.stdout) if r.returncode == 0 else None
    except Exception:
        data = None
    if not data:
        print("ERROR", ref); continue
    s = re.match(r"^https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", data.get("url", ""))
    key = (s.group(1) + "#" + s.group(2)) if s else (repo and repo + "#" + num)
    if data.get("state") == "MERGED" and key:
        print("MERGED", key)
    else:
        print("OPEN", ref, data.get("state", "?"))
PY
)"
[[ -n "$result" ]] || exit 0

recorded=(); notes=""
while read -r kind ref extra; do
  case "$kind" in
    MERGED) pending_add "$sid" "$ref" && recorded+=("$ref") ;;
    AUTO) notes+=" ${ref}: --auto only queues the merge; send the Next message once it has merged." ;;
    ERROR) notes+=" ${ref}: gh could not confirm the merge, so it was NOT recorded; if it merged, send its Next message anyway." ;;
    UNPARSED) notes+=" One gh pr merge had no PR number (pass the number); if it merged, send its Next message anyway." ;;
    OPEN) ;;  # the merge did not happen: nothing to say
  esac
done <<<"$result"

if [[ ${#recorded[@]} -gt 0 ]]; then
  list="$(printf '%s, ' "${recorded[@]}")"; list="${list%, }"
  first="${recorded[0]##*#}"
  msg="Coordinator: merged ${list}. Pending until sent: in THIS turn, read the author's context (mcp__ccd_session_mgmt__get_usage) and send the author one message \"PR #${first} merged. Next: <issue | handover | stand by | done>\" (at or past the soft limit: handover; a per-issue agent: done; write \"PR owner/repo#N merged\" when the same number is pending in two repos). The agent waits after \"PR ready\" and runs only when a message arrives; the Stop hook blocks your turn until it is sent. Then, for a per-issue agent, archive its session (mcp__ccd_session_mgmt__archive_session, name \"Agent: <unit> #<issue>\"); a standing session is archived only on rotation. Update the ledger (review-merge.md, steps 7 and 9). If the author can no longer receive a message: bash \"${plugin}/scripts/next-clear.sh\" ${sid} <owner/repo#N> \"<reason>\". If the app setting auto_archive_on_pr_close is still on, unbind this PR from your session (mcp__ccd_pr__unbind_pr) and ask the owner to turn the setting off.${notes}"
elif [[ -n "$notes" ]]; then
  msg="${generic}${notes}"
else
  exit 0
fi
emit "$msg"
