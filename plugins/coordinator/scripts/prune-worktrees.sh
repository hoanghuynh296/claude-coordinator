#!/usr/bin/env bash
# Remove finished agent worktrees (`.claude/worktrees/*`) under the given roots, safely.
#
# Usage:
#   prune-worktrees.sh <root>... (--sessions <file> | --no-session-check)
#                      [--dry-run | --apply] [--min-age-hours N] [--discard <glob>]...
#
# Lists every directory directly under a `.claude/worktrees/` folder below each root (a root
# that is itself such a directory is checked alone) and removes it only when ALL of these hold:
#   1. it is a registered, unlocked git worktree (a stray folder is reported, never deleted);
#   2. nothing in it was modified for N hours (default 6): files in the worktree (skipping
#      .git, node_modules) and its HEAD, index and reflog in the git dir;
#   3. `git status --porcelain --untracked-files=all` is empty, or every line is a path that
#      matches a --discard glob (bash pattern; `*` also matches `/`);
#   4. HEAD is contained in a remote-tracking branch (`git branch -r --contains HEAD`);
#   5. no live work in it. With `--sessions <file>` (the JSON of
#      `mcp__ccd_session_mgmt__list_sessions`; the audit mode) it is kept when a non-archived
#      session has it (or a folder inside it) as its cwd, or has its branch as `branch` with a
#      PR state other than MERGED/CLOSED, or its branch has an OPEN pull request on GitHub
#      (`gh pr list`; a lookup that fails keeps it). An agent's session cwd is often not its
#      worktree, so the PR checks are what protect a live agent waiting on review.
#      `--no-session-check` skips all of check 5 explicitly. One of the two is required;
#   6. it is not the current directory or a parent of it.
# Removal is `git worktree remove` (with `--force` only when every change matched --discard,
# because git refuses otherwise). Branches are kept, so no commit becomes unreachable.
# Default is --dry-run: it prints what it would remove; --apply removes.
#
# Output: one line per worktree - `REMOVE` / `WOULD REMOVE <path> (<size>)`,
# `KEEP <path>: <reason>`, `STRAY <path>: <reason> (not deleted)` - then a summary with the
# space freed. Exit 0 ok, 1 a removal failed, 2 bad arguments or unreadable sessions file.
# COORDINATOR_GH: the gh binary (tests).
set -uo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "prune-worktrees: $*" >&2; exit 2; }

apply=0; sessions=""; no_session_check=0; min_age_hours=6
roots=(); discards=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) apply=0 ;;
    --apply) apply=1 ;;
    --sessions) [[ $# -ge 2 ]] || die "--sessions needs a file"; sessions="$2"; shift ;;
    --no-session-check) no_session_check=1 ;;
    --min-age-hours) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die "--min-age-hours needs a whole number"
                     min_age_hours="$2"; shift ;;
    --discard) [[ $# -ge 2 && -n "$2" ]] || die "--discard needs a glob"; discards+=("$2"); shift ;;
    -h|--help) usage ;;
    -*) die "unknown option $1" ;;
    *) roots+=("$1") ;;
  esac
  shift
done
[[ ${#roots[@]} -gt 0 ]] || usage
if [[ -n "$sessions" && $no_session_check -eq 1 ]]; then die "pass --sessions or --no-session-check, not both"; fi
if [[ -z "$sessions" && $no_session_check -eq 0 ]]; then
  die "pass --sessions <list_sessions JSON file>, or --no-session-check to skip the live-session check"
fi

# Live session cwds (absolute paths, as given and resolved) and live branches, one per line.
live_cwds=""; live_branches=""; gh="${COORDINATOR_GH:-gh}"
if [[ -n "$sessions" ]]; then
  [[ -r "$sessions" ]] || die "cannot read sessions file $sessions"
  command -v jq >/dev/null 2>&1 || die "jq is required for --sessions"
  jqa='if type == "array" then . else (.sessions // error("no session array")) end'
  total="$(jq -r "$jqa | length" "$sessions" 2>/dev/null)" \
    || die "sessions file $sessions is not list_sessions JSON"
  fields="$(jq -r "$jqa | map(select((.cwd // \"\") != \"\" or (.branch // \"\") != \"\")) | length" "$sessions" 2>/dev/null)" \
    || die "sessions file $sessions is not list_sessions JSON"
  if [[ "$total" -gt 0 && "$fields" -eq 0 ]]; then
    die "sessions file $sessions has $total sessions but no cwd or branch field: not list_sessions JSON"
  fi
  raw="$(jq -r "$jqa | .[] | select(.isArchived != true) | .cwd // empty" "$sessions")"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    live_cwds+="${c%/}"$'\n'
    if [[ -d "$c" ]]; then live_cwds+="$(cd "$c" && pwd -P)"$'\n'; fi
  done <<<"$raw"
  live_branches="$(jq -r "$jqa | .[] | select(.isArchived != true) | select((.branch // \"\") != \"\")
      | select(((.prState // .pr.state // \"\") | ascii_upcase) as \$s | (\$s != \"MERGED\" and \$s != \"CLOSED\"))
      | .branch" "$sessions")"
  command -v "$gh" >/dev/null 2>&1 || die "gh is required for --sessions (open-PR check)"
fi

# owner/repo of a GitHub remote URL, empty if it is not one.
gh_repo() {
  local u="$1"
  u="${u%.git}"; u="${u%/}"
  case "$u" in
    git@github.com:*) u="${u#git@github.com:}" ;;
    ssh://git@github.com/*) u="${u#ssh://git@github.com/}" ;;
    https://github.com/*|http://github.com/*) u="${u#*://github.com/}" ;;
    *) return 0 ;;
  esac
  [[ "$u" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s' "$u"
}

# Prints why the worktree's branch is live (a session or an open PR), empty when it is not.
branch_live() { # dir
  local d="$1" br url repo b n
  br="$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null)" || br=""
  [[ -n "$br" ]] || return 0   # detached HEAD: no branch, so no session branch and no PR
  while IFS= read -r b; do
    [[ -n "$b" && "$b" == "$br" ]] && { printf 'a live session is on branch %s' "$br"; return 0; }
  done <<<"$live_branches"
  url="$(git -C "$d" config --get remote.origin.url 2>/dev/null)" || url=""
  repo="$(gh_repo "$url")"
  [[ -n "$repo" ]] || { printf 'cannot look up PRs for branch %s (origin is not a GitHub repo)' "$br"; return 0; }
  n="$("$gh" pr list -R "$repo" --head "$br" --state open --json number --jq 'length' 2>/dev/null)" \
    || { printf 'PR lookup for %s failed' "$br"; return 0; }
  [[ "$n" =~ ^[0-9]+$ ]] || { printf 'PR lookup for %s failed' "$br"; return 0; }
  [[ "$n" -eq 0 ]] || printf 'branch %s has an open PR on %s' "$br" "$repo"
}

here="$(pwd -P)"
removed=0; kept=0; stray=0; failed=0; freed_kb=0

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else printf "%.0f MB", k/1024 }'; }
keep() { kept=$((kept+1)); echo "KEEP $1: $2"; }

# Prints the first path modified in the last N minutes, empty if none.
recent_change() { # dir gitdir minutes
  local d="$1" g="$2" m="$3" f
  [[ "$m" -gt 0 ]] || return 0   # --min-age-hours 0: no age check
  f="$(find "$d" \( -name .git -o -name node_modules \) -prune -o -mmin "-$m" -print 2>/dev/null | head -1)"
  if [[ -z "$f" && -n "$g" ]]; then
    f="$(find "$g/HEAD" "$g/index" "$g/logs/HEAD" -mmin "-$m" -print 2>/dev/null | head -1)"
  fi
  printf '%s' "$f"
}

matches_discard() { # path
  local g
  for g in ${discards[@]+"${discards[@]}"}; do
    # shellcheck disable=SC2053
    [[ "$1" == $g ]] && return 0
  done
  return 1
}

check_one() { # worktree dir (resolved)
  local d="$1" top gitdir listed=0 locked=0 cur="" line st changes force=0 p c

  # 1. A registered, unlocked worktree whose top level is this folder.
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -n "$top" ]]; then top="$(cd "$top" && pwd -P)"; fi
  if [[ "$top" != "$d" || ! -f "$d/.git" ]]; then
    stray=$((stray+1)); echo "STRAY $d: not a git worktree (not deleted)"; return
  fi
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur="${line#worktree }"; [[ -d "$cur" ]] && cur="$(cd "$cur" && pwd -P)" ;;
      locked*) [[ "$cur" == "$d" ]] && locked=1 ;;
    esac
    [[ "$cur" == "$d" ]] && listed=1
  done < <(git -C "$d" worktree list --porcelain 2>/dev/null)
  if [[ $listed -eq 0 ]]; then
    stray=$((stray+1)); echo "STRAY $d: not registered with its repository (not deleted)"; return
  fi
  [[ $locked -eq 0 ]] || { keep "$d" "locked"; return; }

  # 6. Not where we stand.
  if [[ "$here" == "$d" || "$here" == "$d/"* ]]; then keep "$d" "current directory"; return; fi

  # 5. No live session in it.
  if [[ -n "$live_cwds" ]]; then
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      if [[ "$c" == "$d" || "$c" == "$d/"* ]]; then keep "$d" "a live session works in $c"; return; fi
    done <<<"$live_cwds"
  fi
  if [[ -n "$sessions" ]]; then
    p="$(branch_live "$d")"
    if [[ -n "$p" ]]; then keep "$d" "$p"; return; fi
  fi

  # 2. Old enough (checked before any git command that could touch the index).
  gitdir="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  p="$(recent_change "$d" "$gitdir" $((min_age_hours * 60)))"
  if [[ -n "$p" ]]; then p="${p#$d}"; p="${p#/}"; keep "$d" "modified in the last ${min_age_hours}h (${p:-.})"; return; fi

  # 3. Clean, or only changes the caller allowed to discard.
  st="$(git -C "$d" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null)" \
    || { keep "$d" "git status failed"; return; }
  if [[ -n "$st" ]]; then
    changes=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      changes=$((changes+1))
      p="${line:3}"
      if [[ "$p" == *" -> "* || "$p" == \"* ]] || ! matches_discard "$p"; then
        keep "$d" "uncommitted changes (first not discardable: ${line})"; return
      fi
    done <<<"$st"
    force=1
  fi

  # 4. HEAD is on a remote.
  if [[ -z "$(git -C "$d" branch -r --contains HEAD 2>/dev/null)" ]]; then
    keep "$d" "HEAD $(git -C "$d" rev-parse --short HEAD 2>/dev/null) is not in any remote branch (unpushed)"; return
  fi

  local kb note=""; kb="$(size_kb "$d")"
  [[ $force -eq 1 ]] && note=", discarding $changes generated file(s)"
  if [[ $apply -eq 0 ]]; then
    removed=$((removed+1)); freed_kb=$((freed_kb + kb))
    echo "WOULD REMOVE $d ($(human "$kb")$note)"; return
  fi
  local args=(worktree remove)
  [[ $force -eq 1 ]] && args+=(--force)
  if git -C "$d" "${args[@]}" "$d" >/dev/null 2>"${TMPDIR:-/tmp}/prune-wt.$$"; then
    removed=$((removed+1)); freed_kb=$((freed_kb + kb))
    echo "REMOVE $d ($(human "$kb")$note)"
  else
    failed=$((failed+1))
    echo "FAILED $d: $(tr '\n' ' ' <"${TMPDIR:-/tmp}/prune-wt.$$")"
  fi
  rm -f "${TMPDIR:-/tmp}/prune-wt.$$"
}

for root in "${roots[@]}"; do
  [[ -d "$root" ]] || die "not a directory: $root"
  root="$(cd "$root" && pwd -P)"
  # A root that is itself one worktree (`.../.claude/worktrees/<name>`): check only it.
  if [[ "$(dirname "$root")" == */.claude/worktrees ]]; then check_one "$root"; continue; fi
  while IFS= read -r -d '' wtdir; do
    while IFS= read -r -d '' d; do
      check_one "$(cd "$d" && pwd -P)"
    done < <(find "$wtdir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  done < <(find "$root" \( -name node_modules -o -name .git \) -prune -o \
             -type d -path '*/.claude/worktrees' -print0 -prune 2>/dev/null)
done

if [[ $apply -eq 1 ]]; then
  echo "Summary: $removed removed, $kept kept, $stray stray, $failed failed; freed $(human "$freed_kb")"
else
  echo "Summary (dry run; --apply removes): $removed to remove, $kept kept, $stray stray; would free $(human "$freed_kb")"
fi
[[ $failed -eq 0 ]]
