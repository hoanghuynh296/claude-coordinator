#!/usr/bin/env bash
# The mechanical part of review-merge (steps 1, 6 and 9's bookkeeping) in one call, at most 6
# lines of output. Run it only after the review passed (steps 3 to 5); it checks, merges and
# records, it does not review.
#
# Usage: merge-pr.sh <owner/repo> <N> <head sha> [--session <id>] [--ledger <dir>]
#                    [--method merge|squash|rebase] [--next "<text>"]
#                    [--per-issue "<author session name>"] [--repo-dir <local clone>]
#                    [--owner-approved]
#
#   1. refuses, with one line why and no merge (exit 1), when the PR is not open, its head is not
#      <head sha> (full or a prefix of 7+), or CI on that head is red, pending or has no checks,
#      or its base is a branch the profile's "Owner approves merges into:" line names (none, a
#      <placeholder> or no line: no branch) and --owner-approved is not given
#   2. `gh pr merge <N> --<method> --delete-branch --match-head-commit <sha>`; the method is
#      --method, else the first word after "Merge method:" in <ledger>/coordination/PROFILE.md
#      (squash or rebase; a <placeholder> is ignored), else merge
#   3. base is not the default branch → closes the PR's linked issues ("Closes #N" fires only on
#      the default branch), each with the comment "Merged in <owner/repo>#<N>"
#   4. records the PR as pending its Next message in the coordinator's hook state (the
#      merge-reminder hook does not see a `gh pr merge` inside a script), so the Stop guard holds
#      the turn until "PR #<N> merged. Next: ..." is sent. Exempt, as in the hook: heads
#      release/*, backmerge/*, coordinator/*, and PRs by $COORDINATOR_GH_LOGIN
#   5. --per-issue "<name>" (and --next not "(same session)"): prints the session to archive and,
#      with --repo-dir, removes the PR's worktree under <repo>/.claude/worktrees/ with
#      prune-worktrees.sh (kept when dirty or unpushed: its KEEP line is printed)
#
# --session: the coordinator's session id (Claude Code ${CLAUDE_SESSION_ID}, Antigravity the
# Conversation ID; default $COORDINATOR_SESSION_ID). --next: the text after "Next: " (default done).
# --ledger is read only: commit the ledger once at the end of the turn with ledger-commit.sh.
# Output (at most 6 lines):
#   merge-pr: <repo>#<N> merged into <base> (<method>, <sha7>)[; closed <issues>]
#   send to <author>: PR #<N> merged. Next: <text>      (or: no Next message: exempt head <ref>)
#   archive: <name>                                     (--per-issue only)
#   worktree: removed <path> | kept: <reason> | none for <branch>   (--per-issue with --repo-dir)
#   pending Next recorded for <session> | WARNING: ...
# Exit: 0 merged, 1 refused (nothing merged), 2 usage or gh error, 3 the merge failed (the PR is
# not MERGED afterwards), 4 merge state unknown (the pending Next is recorded anyway: check it).
# A nonzero `gh pr merge` on a PR that is MERGED afterwards counts as merged (noted on line 1).
# COORDINATOR_GH: the gh binary (tests). Needs python3. Same output on Claude Code and Antigravity.
set -uo pipefail

# shellcheck source=../hooks/lib.sh
. "$(dirname "$0")/../hooks/lib.sh"
here="$(cd "$(dirname "$0")" && pwd -P)"
gh="${COORDINATOR_GH:-gh}"

usage() { sed -n '6,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "merge-pr: $*"; exit 2; }

repo="${1:-}"; num="${2:-}"; sha="${3:-}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$num" =~ ^[0-9]+$ && "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || usage
shift 3
sid="${COORDINATOR_SESSION_ID:-}"; ledger=""; method=""; next="done"; per_issue=""; repo_dir=""
owner_ok=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) [[ $# -ge 2 ]] || usage; sid="$2"; shift 2 ;;
    --ledger) [[ $# -ge 2 ]] || usage; ledger="$2"; shift 2 ;;
    --method) [[ $# -ge 2 && "$2" =~ ^(merge|squash|rebase)$ ]] || usage; method="$2"; shift 2 ;;
    --next) [[ $# -ge 2 && -n "$2" ]] || usage; next="$2"; shift 2 ;;
    --per-issue) [[ $# -ge 2 && -n "$2" ]] || usage; per_issue="$2"; shift 2 ;;
    --repo-dir) [[ $# -ge 2 && -d "$2" ]] || usage; repo_dir="$2"; shift 2 ;;
    --owner-approved) owner_ok=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
command -v python3 >/dev/null 2>&1 || die "python3 missing"
next="${next//$'\n'/ }"
prof="${ledger:+$ledger/coordination/PROFILE.md}"
[[ -n "$prof" && -f "$prof" ]] || prof=""
# Branches whose merges the owner approves: the words after "Owner approves merges into:",
# split on commas and spaces, each without backticks, quotes, asterisks or a trailing period;
# "none", a <placeholder> or no line means none (the kit default: the coordinator merges).
owner_branches=""
if [[ -n "$prof" ]]; then
  val="$(sed -n 's/.*[Oo]wner approves merges into:[[:space:]]*//p' "$prof" | head -n 1)"
  set -f
  for w in $(printf '%s' "$val" | tr ',' ' '); do
    w="$(printf '%s' "$w" | tr -d '`"*'"'")"; w="${w%.}"; w="${w%;}"
    case "$w" in "") continue ;; "<"*|[Nn]one|"("*) break ;; esac
    owner_branches+=" $w"
  done
  set +f
fi
if [[ -z "$method" ]]; then
  method=merge
  if [[ -n "$prof" ]]; then
    # The first word after "Merge method:", without leading spaces, backticks, quotes or
    # asterisks (`squash`, "squash", **squash**, **Merge method:** squash); a template
    # placeholder (<...>) counts as unset.
    val="$(sed -n 's/.*[Mm]erge [Mm]ethod:[[:space:]]*//p' "$prof" | head -n 1)"
    while [[ "$val" == [[:space:]\`\"\'*]* ]]; do val="${val:1}"; done
    case "$val" in
      "<"*) ;;
      [Ss]quash*) method=squash ;;
      [Rr]ebase*) method=rebase ;;
    esac
  fi
fi

# 1. State, head, CI. The python part prints key=value lines, or "refuse <why>" / "error <why>".
facts="$(python3 -I - "$gh" "$repo" "$num" "$sha" <<'PY'
import json, subprocess, sys
gh, repo, num, want = sys.argv[1:5]
want = want.lower()
def run(args):
    p = subprocess.run([gh] + args, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, (p.stderr or p.stdout).strip().splitlines()[-1:] or [""]
rc, out, err = run(["pr", "view", num, "-R", repo, "--json",
                    "state,url,headRefOid,headRefName,baseRefName,author,closingIssuesReferences"])
if rc != 0:
    print("error gh pr view: " + err[0]); sys.exit()
try:
    v = json.loads(out)
except ValueError:
    print("error gh pr view: not JSON"); sys.exit()
state = (v.get("state") or "").upper()
head = (v.get("headRefOid") or "").lower()
if state != "OPEN":
    print(f"refuse {repo}#{num} is {state.lower() or 'unknown'}, not open"); sys.exit()
if not head.startswith(want):
    print(f"refuse stale head: {repo}#{num} head is {head[:7]}, reviewed {want[:7]}"); sys.exit()
rc, out, err = run(["pr", "checks", num, "-R", repo, "--json", "name,bucket"])
checks = []
if rc == 0 or out.strip().startswith("["):
    try:
        checks = json.loads(out or "[]")
    except ValueError:
        print("error gh pr checks: not JSON"); sys.exit()
elif "no checks reported" not in err[0]:
    print("error gh pr checks: " + err[0]); sys.exit()
if not checks:
    print(f"refuse no CI checks on {head[:7]}: merge by hand only if the profile's gate has no CI"); sys.exit()
red = [c.get("name", "?") for c in checks if c.get("bucket") in ("fail", "cancel")]
pend = [c.get("name", "?") for c in checks if c.get("bucket") == "pending"]
if red:
    print(f"refuse CI red on {head[:7]}: {', '.join(red)}"); sys.exit()
if pend:
    print(f"refuse CI pending on {head[:7]}: {', '.join(pend)} (wait for ci-watch.sh)"); sys.exit()
rc, out, err = run(["repo", "view", repo, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"])
default = out.strip() if rc == 0 else ""
issues = []
for i in v.get("closingIssuesReferences") or []:
    r = i.get("repository") or {}
    owner = (r.get("owner") or {}).get("login")
    name = r.get("name")
    ir = f"{owner}/{name}" if owner and name else repo
    if i.get("number"):
        issues.append(f"{ir}#{i['number']}")
import re
u = re.match(r"^https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", v.get("url") or "")
print("ok")
print("key=" + (u.group(1) + "#" + u.group(2) if u else f"{repo}#{num}"))
print("head=" + head)
print("headref=" + (v.get("headRefName") or ""))
print("base=" + (v.get("baseRefName") or ""))
print("default=" + default)
print("author=" + ((v.get("author") or {}).get("login") or ""))
print("issues=" + " ".join(issues))
PY
)" || die "python3 failed"
first="${facts%%$'\n'*}"
case "$first" in
  ok) ;;
  refuse\ *) echo "merge-pr: refused: ${first#refuse }"; exit 1 ;;
  error\ *) echo "merge-pr: error: ${first#error }"; exit 2 ;;
  *) die "unexpected: $first" ;;
esac
fact() { printf '%s\n' "$facts" | sed -n "s/^$1=//p" | head -n 1; }
head="$(fact head)"; headref="$(fact headref)"; base="$(fact base)"; default="$(fact default)"
author="$(fact author)"; issues="$(fact issues)"; key="$(fact key)"
if [[ $owner_ok -eq 0 && " $owner_branches " == *" $base "* ]]; then
  echo "merge-pr: refused: merges into $base need the owner's approval (PROFILE.md \"Owner approves merges into:\"); ask once, then rerun with --owner-approved"
  exit 1
fi

# Record the PR as pending its Next (registered coordinator only) and print the line to send.
reg_ok=0; [[ -n "$sid" ]] && registration_file "$sid" >/dev/null && reg_ok=1
record_next() {
  if [[ -z "$sid" ]]; then
    state_line="WARNING: no --session: pending Next not recorded, the Stop guard will not hold the turn"
  elif [[ $reg_ok -eq 0 ]]; then
    state_line="WARNING: $sid is not a registered coordinator: pending Next not recorded"
  elif pending_add "$sid" "$key"; then
    state_line="pending Next recorded for $sid; the Stop guard holds the turn until it is sent"
  else
    state_line="WARNING: could not record the pending Next for $sid"
  fi
  ref="#$num"
  if [[ $reg_ok -eq 1 && "$(pending_keys "$sid" "$num" | grep -c . || true)" -gt 1 ]]; then ref="$key"; fi
  echo "send to ${per_issue:-the author}: PR $ref merged. Next: $next"
}

# 2. Merge. gh may exit nonzero although the merge landed (branch delete failed, timeout), so the
# PR's state decides, never the exit code.
merge_rc=0
out="$("$gh" pr merge "$num" -R "$repo" "--$method" --delete-branch --match-head-commit "$head" 2>&1)" || merge_rc=$?
merge_err="$(printf '%s\n' "$out" | grep . | tail -1)"
state="$("$gh" pr view "$num" -R "$repo" --json state --jq .state 2>/dev/null)" || state=""
if [[ -z "$state" ]]; then
  echo "merge-pr: $repo#$num merge state unknown (gh pr merge exit $merge_rc${merge_err:+: $merge_err}): check it and send the Next anyway"
  if next_exempt "$headref" "$author"; then echo "no Next message: exempt head $headref"; exit 4; fi
  record_next; echo "$state_line"; exit 4
fi
if [[ "$state" != "MERGED" ]]; then
  echo "merge-pr: merge failed: $repo#$num is $state${merge_err:+: $merge_err}"
  exit 3
fi
result="merge-pr: $repo#$num merged into $base ($method, ${head:0:7})"
[[ $merge_rc -ne 0 ]] && result+="; gh pr merge exited $merge_rc (${merge_err:-no message}; check the branch was deleted)"

# 3. Linked issues when the base is not the default branch.
if [[ -n "$issues" && -n "$default" && "$base" != "$default" ]]; then
  closed=""; failed=""
  for i in $issues; do
    if "$gh" issue close "${i##*#}" -R "${i%#*}" --comment "Merged in $repo#$num" >/dev/null 2>&1; then
      closed+="${closed:+, }$i"
    else
      failed+="${failed:+, }$i"
    fi
  done
  [[ -n "$closed" ]] && result+="; closed $closed"
  [[ -n "$failed" ]] && result+="; could not close $failed"
elif [[ -n "$issues" && -z "$default" ]]; then
  result+="; default branch unknown: check $issues"
fi
echo "$result"

# 4. Next: exempt heads, else record it pending for the Stop guard.
if next_exempt "$headref" "$author"; then
  echo "no Next message: exempt head $headref"
  exit 0
fi
record_next

# 5. A per-issue author: archive it and check its worktree (not when it goes on, same session).
if [[ -n "$per_issue" && "$next" != *"(same session)"* ]]; then
  echo "archive: $per_issue"
  if [[ -n "$repo_dir" ]]; then
    wt="$(git -C "$repo_dir" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$headref" '
      /^worktree / {p=substr($0, 10)} $0 == "branch " b && p ~ /\/\.claude\/worktrees\// {print p; exit}')"
    if [[ -z "$wt" ]]; then
      echo "worktree: none for $headref"
    else
      pr_out="$(bash "$here/prune-worktrees.sh" "$wt" --no-session-check --min-age-hours 0 --apply 2>&1)"
      line="$(printf '%s\n' "$pr_out" | grep -E '^(REMOVE|KEEP|STRAY)' | head -1)"
      case "$line" in
        REMOVE*) echo "worktree: removed $wt" ;;
        KEEP*) echo "worktree: kept: ${line#KEEP } (tell the agent's issue)" ;;
        *) echo "worktree: check $wt: $(printf '%s\n' "$pr_out" | grep . | tail -1)" ;;
      esac
    fi
  fi
fi
echo "$state_line"
exit 0
