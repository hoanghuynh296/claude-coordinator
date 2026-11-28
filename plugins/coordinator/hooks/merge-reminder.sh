#!/usr/bin/env bash
# PostToolUse hook for Bash. After a registered coordinator merges a PR with `gh pr merge <N>`:
#   - records owner/repo#N as "pending Next" in the session's state dir (lib.sh, state_dir);
#     the Stop hook (next-guard.sh) blocks the end of the turn until the author got
#     "PR #N merged. Next: ..." (cleared by next-sent.sh) or the coordinator cleared it with
#     scripts/next-clear.sh;
#   - reminds it to send that message and to archive a per-issue agent's session.
# The command is first reduced to what the shell would run (heredoc bodies and comments removed),
# then split like a shell would (python shlex): `gh [-R x] pr merge` at the start of a command
# counts (also after sudo/env/xargs/... and inside `bash -lc '...'`, eval, $(...) and backticks).
# Heredoc bodies, comments, quoted arguments (git commit -m "..") and echo/printf arguments are
# silent. Whether the merge happened is not guessed from the output or the exit code (a
# `; echo ok` or `|| true` hides a failure, `&& git pull` can fail after a real merge): each PR is
# looked up with `gh pr view` and recorded only when its state is MERGED, whatever the exit code
# (with --auto too: gh merges a ready PR at once). All lookups share one deadline
# (COORDINATOR_GH_DEADLINE, default 20 s; hooks.json gives the hook 45 s). Fail open: when gh
# cannot answer, when a `gh ... pr merge` outside a plain argument is seen but not parsed, or when
# the parser itself fails, nothing is recorded and the reminder is shown anyway (only a state gh reports as OPEN stays
# silent). After a `cd` (and no -R / GH_REPO=) the PR is not looked up: the reminder is shown. A user prompt is not read here.
# Exempt PRs (no author to tell what is next) are not recorded: a PR whose head branch is
# release/*, backmerge/* or coordinator/* (the coordinator's own branches; an agent that names its
# branch coordinator/* is exempt too), or whose author is $COORDINATOR_GH_LOGIN. Do NOT set
# COORDINATOR_GH_LOGIN to an account the agents share: every agent PR would be exempt. The decision
# is made here, from the same `gh pr view` that confirms the merge, so next-guard.sh makes no gh
# call. Unregistered sessions and other commands: no output, no state. Needs python3 to record.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
input="$(cat)"
sid="$(hook_sid "$input")" || exit 0
ag=0; is_antigravity "$input" && ag=1
silent() { (( ag )) && printf '{}\n'; exit 0; }
registration_file "$sid" >/dev/null || silent

cmd="$(json_get "$input" tool_input.command)"
[[ -z "$cmd" ]] && cmd="$(json_get "$input" toolCall.args.CommandLine)"
[[ "$cmd" =~ gh[[:space:]].*pr[[:space:]]+merge ]] || silent
# The exit code is not read: a merge can succeed and a later `&& git pull` or --delete-branch
# fail, so every outcome goes through `gh pr view` below (and an interrupted command too).
cwd="$(json_get "$input" cwd)"

generic="Coordinator: a PR may have been merged. If so, send its author \"PR #<N> merged. Next: <issue | handover | stand by | done>\" in this turn (review-merge.md, step 9); for a per-issue agent, archive its session afterwards (mcp__ccd_session_mgmt__archive_session, alone in its own message); a standing session is archived only on rotation."
emit() {
  if (( ag )); then
    printf '{}\n'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$1")"
  fi
}

if ! command -v python3 >/dev/null 2>&1; then emit "$generic (python3 missing: the merge was not recorded.)"; exit 0; fi

# One line per finding: EXEMPT <repo#N> | MERGED <repo#N> | OPEN <ref> <state> | ERROR <ref> | AUTO <ref> | CD <ref> | UNPARSED
# The reader is read into a variable first, not fed as a heredoc inside "$(...)": macOS
# /bin/bash 3.2 scans a heredoc body inside "$(...)" for quotes, and the backticks below
# end in "unexpected EOF while looking for matching ``'" there.
IFS= read -r -d '' reader <<'PY' || true
import json, os, re, shlex, subprocess, sys, time
gh, cwd = sys.argv[1], sys.argv[2]
try:
    deadline = time.monotonic() + float(sys.argv[4])   # one budget for every gh call
except (IndexError, ValueError):
    deadline = time.monotonic() + 20
def sanitize(text):
    """The command as the shell would run it: heredoc bodies and comments removed, unquoted
    newlines turned into ';'. Quoted text is kept (the lexer reads it as one word)."""
    out, i, n, q = [], 0, len(text), None
    pending = []                        # heredoc delimiters waiting for the next newline
    while i < n:
        c = text[i]
        if q:
            out.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                out.append(text[i+1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c == "\\" and i + 1 < n:
            out.append(c + text[i+1]); i += 2; continue
        if c in "'\"":
            q = c; out.append(c); i += 1; continue
        if c == "#" and (i == 0 or text[i-1] in " \t\n;&|("):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("$((", i):     # arithmetic: its << is a shift, not a heredoc
            d, j = 0, i + 1
            while j < n:
                d += (text[j] == "(") - (text[j] == ")")
                j += 1
                if d == 0:
                    break
            out.append(text[i:j]); i = j; continue
        if text.startswith("<<", i) and not text.startswith("<<<", i):
            m = re.match(r"<<(-?)[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([A-Za-z0-9_.-]+))", text[i:])
            if m:
                pending.append((m.group(1) == "-", m.group(2) or m.group(3) or m.group(4)))
                i += m.end(); out.append(" "); continue
        if c == "\n":
            out.append(" ; "); i += 1
            for strip, word in pending:  # skip each body up to its delimiter line
                while i < n:
                    j = text.find("\n", i); j = n if j < 0 else j
                    line = text[i:j]; i = min(j + 1, n)
                    if (line.strip("\t") if strip else line) == word:
                        break
            pending = []
            continue
        out.append(c); i += 1
    return "".join(out)

def is_sep(t):    # shlex glues adjacent punctuation: "));" and "&&" are one token
    return bool(re.fullmatch(r"[();&|]+", t))
with_value = {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email",
              "--match-head-commit"}
merges = []

def scan(cmd, depth=0):
    cmd = sanitize(cmd)
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        toks = list(lex)
    except ValueError:
        toks = cmd.split()
    i, start, segstart, cdseen, envrepo = 0, True, 0, False, None
    while i < len(toks):
        t = toks[i]
        if is_sep(t):
            start = True; i += 1; segstart = i; envrepo = None; continue
        if start and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):   # VAR=value prefix
            if t.startswith("GH_REPO="):
                envrepo = t.split("=", 1)[1]
            i += 1; continue
        if start and t in ("cd", "pushd", "popd"):    # later commands run in another directory
            cdseen = True
        # words after which a new command starts: shell keywords and command prefixes
        if start and t in ("then", "do", "else", "elif", "if", "while", "until", "{", "!", "time",
                           "sudo", "command", "exec", "env", "xargs", "nohup", "nice", "timeout"):
            i += 1
            while i < len(toks) and not is_sep(toks[i]) and toks[i] != "gh" and \
                    not re.match(r"^(ba|z|da|k)?sh$|^eval$", toks[i]):   # their options and values
                i += 1
            continue
        # bash -c '...' / sh -c / eval: the string is a command line too
        if start and depth < 3 and re.match(r"^(ba|z|da|k)?sh$", t) and any(re.match(r"^-[a-zA-Z]*c$", x) for x in toks[i+1:i+4]):
            k = next(i + 1 + m for m, x in enumerate(toks[i+1:i+4]) if re.match(r"^-[a-zA-Z]*c$", x))
            if k + 1 < len(toks):
                scan(toks[k+1], depth + 1)
            i = k + 2; start = False; continue
        if start and depth < 3 and t == "eval" and i + 1 < len(toks):
            scan(" ".join(toks[i+1:]), depth + 1)
            return
        k, grepo = i + 1, envrepo
        while start and t == "gh" and k < len(toks) and toks[k].startswith("-") and not is_sep(toks[k]):
            if toks[k] in ("-R", "--repo") and k + 1 < len(toks):
                grepo = toks[k+1]; k += 2
            else:
                if toks[k].startswith("--repo="):
                    grepo = toks[k].split("=", 1)[1]
                k += 1
        if start and t == "gh" and toks[k:k+2] == ["pr", "merge"]:
            j, pr, repo, auto = k + 2, None, grepo, False
            while j < len(toks) and not is_sep(toks[j]):
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
            merges.append((pr, repo, auto, cdseen and repo is None))
            i = j; start = False; continue
        if t == "gh" and depth < 5:      # gh ... pr merge somewhere we did not read as a command
            k = i + 1
            while k < len(toks) and toks[k].startswith("-") and not is_sep(toks[k]):
                k += 2 if toks[k] in ("-R", "--repo") else 1
            seg = toks[segstart:i]
            if toks[k:k+2] == ["pr", "merge"] and not (seg and seg[0] in ("echo", "printf")):
                merges.append((None, None, False, False))
        start = False; i += 1
    # $(...) and `...`, also inside double quotes (single-quoted text is literal)
    if depth < 3:
        plain = re.sub(r"'[^']*'", "''", cmd)
        for m in re.finditer(r"\$\(([^()]*)\)|`([^`]*)`", plain):
            scan(m.group(1) or m.group(2) or "", depth + 1)

try:
    scan(sys.argv[3])
except Exception:
    merges.append((None, None, False, False))
merges[:] = list(dict.fromkeys(merges))
# no merge at command position (heredoc body, string, comment, echo): nothing ran, say nothing
for pr, repo, auto, cd in merges:
    m = re.match(r"^#?(\d+)$", pr or "")
    u = re.match(r"^https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", pr or "")
    if u:
        repo, num = repo or u.group(1), u.group(2)
    elif m:
        num = m.group(1)
    else:
        print("UNPARSED"); continue
    ref = (repo + "#" + num) if repo else ("#" + num)
    if cd:
        print("CD", ref); continue
    left = deadline - time.monotonic()
    if left <= 0.2:
        print("ERROR", ref); continue
    args = [gh, "pr", "view", num, "--json", "state,url,headRefName,author"] + (["-R", repo] if repo else [])
    try:
        r = subprocess.run(args, cwd=cwd if os.path.isdir(cwd) else None, capture_output=True,
                           text=True, timeout=left)
        data = json.loads(r.stdout) if r.returncode == 0 else None
    except Exception:
        data = None
    if not data:
        print("ERROR", ref); continue
    s = re.match(r"^https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", data.get("url", ""))
    key = (s.group(1) + "#" + s.group(2)) if s else (repo and repo + "#" + num)
    head = data.get("headRefName") or ""
    login = os.environ.get("COORDINATOR_GH_LOGIN", "")
    who = (data.get("author") or {}).get("login", "")
    if data.get("state") == "MERGED" and key and (re.match(r"^(release|backmerge|coordinator)/", head) or (login and who == login)):
        print("EXEMPT", key)           # release / back-merge / coordinator PR: nobody to tell
    elif data.get("state") == "MERGED" and key:
        print("MERGED", key)          # also --auto on a PR that was ready: gh merged it at once
    elif auto:
        print("AUTO", ref)
    else:
        print("OPEN", ref, data.get("state", "?"))
PY
result="$(python3 -I -c "$reader" "${COORDINATOR_GH:-gh}" "${cwd:-$PWD}" "$cmd" "${COORDINATOR_GH_DEADLINE:-20}")" \
  || result="UNPARSED"   # a crash of the reader reminds instead of going silent

recorded=(); notes=""
while read -r kind ref extra; do
  case "$kind" in
    MERGED) pending_add "$sid" "$ref" && recorded+=("$ref") ;;
    AUTO) notes+=" ${ref}: --auto queued the merge (not merged yet), so it was NOT recorded; check it (gh pr view <N> --json state,autoMergeRequest) and send the Next message once it has merged (review-merge.md, step 9)." ;;
    ERROR) notes+=" ${ref}: gh could not confirm the merge, so it was NOT recorded; if it merged, send its Next message anyway." ;;
    UNPARSED) notes+=" A gh pr merge whose PR number could not be read (pass a literal number) was NOT recorded; if it merged, send its Next message anyway." ;;
    CD) notes+=" ${ref}: the command changed directory first, so the PR was NOT looked up (it could be in another repo); if it merged, send its Next message anyway." ;;
    EXEMPT) ;;  # exempt PR: not recorded, nothing to say
    OPEN) ;;  # the merge did not happen: nothing to say
  esac
done <<<"$result"
true

if [[ ${#recorded[@]} -gt 0 ]]; then
  list="$(printf '%s, ' "${recorded[@]}")"; list="${list%, }"
  first="${recorded[0]##*#}"
  msg="Coordinator: merged ${list}. Pending until sent: in THIS turn, read the author's context (mcp__ccd_session_mgmt__get_usage) and send the author one message \"PR #${first} merged. Next: <issue | handover | stand by | done>\" (at or past the soft limit: handover; a per-issue agent: done; write \"PR owner/repo#N merged\" when the same number is pending in two repos). The agent waits after \"PR ready\" and runs only when a message arrives; the Stop hook blocks your turn until it is sent. Then, for a per-issue agent, archive its session (mcp__ccd_session_mgmt__archive_session alone in its own message, name \"Agent: <unit> #<issue>\"); a standing session is archived only on rotation. Update the ledger (review-merge.md, steps 7 and 9). If the author can no longer receive a message: bash \"${plugin}/scripts/next-clear.sh\" ${sid} <owner/repo#N> \"<reason>\". If the app setting auto_archive_on_pr_close is still on, unbind this PR from your session (mcp__ccd_pr__unbind_pr) and ask the owner to turn the setting off.${notes}"
elif [[ -n "$notes" ]]; then
  msg="${generic}${notes}"
else
  silent
fi
emit "$msg"
