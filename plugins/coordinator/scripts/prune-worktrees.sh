#!/usr/bin/env bash
# Remove finished agent worktrees (`.claude/worktrees/*`) under the given roots, safely.
#
# Usage:
#   prune-worktrees.sh <root>... (--sessions <file> | --no-session-check)
#                      [--dry-run | --apply] [--min-age-hours N] [--discard <glob>]...
#
# Lists every directory directly under a `.claude/worktrees/` folder below each root and
# removes it only when ALL of these hold:
#   1. it is a registered, unlocked git worktree (a stray folder is reported, never deleted);
#   2. nothing in it was modified for N hours (default 6): files in the worktree (skipping
#      .git, node_modules) and its HEAD, index and reflog in the git dir;
#   3. `git status --porcelain --untracked-files=all` is empty, or every line is a path that
#      matches a --discard glob (bash pattern; `*` also matches `/`);
#   4. HEAD is contained in a remote-tracking branch (`git branch -r --contains HEAD`);
#   5. no non-archived session has it (or a folder inside it) as its cwd: `--sessions <file>`
#      is the JSON of `mcp__ccd_session_mgmt__list_sessions` (fields cwd, isArchived);
#      `--no-session-check` skips this check explicitly. One of the two is required;
#   6. it is not the current directory or a parent of it.
# Removal is `git worktree remove` (with `--force` only when every change matched --discard,
# because git refuses otherwise). Branches are kept, so no commit becomes unreachable.
# Default is --dry-run: it prints what it would remove; --apply removes.
#
# Output: one line per worktree - `REMOVE` / `WOULD REMOVE <path> (<size>)`,
# `KEEP <path>: <reason>`, `STRAY <path>: <reason> (not deleted)` - then a summary with the
# space freed. Exit 0 ok, 1 a removal failed, 2 bad arguments or unreadable sessions file.
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

# Live session cwds, one per line (absolute paths, both as given and resolved).
live_cwds=""
if [[ -n "$sessions" ]]; then
  [[ -r "$sessions" ]] || die "cannot read sessions file $sessions"
  command -v jq >/dev/null 2>&1 || die "jq is required for --sessions"
  raw="$(jq -r 'if type == "array" then . else (.sessions // error("no session array")) end
                | .[] | select(.isArchived != true) | .cwd // empty' "$sessions" 2>/dev/null)" \
    || die "sessions file $sessions is not list_sessions JSON"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    live_cwds+="${c%/}"$'\n'
    if [[ -d "$c" ]]; then live_cwds+="$(cd "$c" && pwd -P)"$'\n'; fi
  done <<<"$raw"
fi

here="$(pwd -P)"
removed=0; kept=0; stray=0; failed=0; freed_kb=0

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else printf "%.0f MB", k/1024 }'; }
keep() { kept=$((kept+1)); echo "KEEP $1: $2"; }

# Prints the first path modified in the last N minutes, empty if none.
recent_change() { # dir gitdir minutes
  local d="$1" g="$2" m="$3" f
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

  # 2. Old enough (checked before any git command that could touch the index).
  gitdir="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  p="$(recent_change "$d" "$gitdir" $((min_age_hours * 60)))"
  if [[ -n "$p" ]]; then keep "$d" "modified in the last ${min_age_hours}h (${p#$d/})"; return; fi

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
