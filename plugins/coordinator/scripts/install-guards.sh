#!/usr/bin/env bash
# Install the kit's mechanical guards into unit checkouts.
# Usage: install-guards.sh [--settings] [--protect "main master"] [--tools "<groups>"] [--force] <repo-dir>...
#
#   For each repo dir:
#     - installs scripts/pre-push-guard.sh as the repo's pre-push hook (shared by all its
#       worktrees). An existing pre-push hook that is not ours is kept, and the install is
#       refused unless --force (then the old hook is saved as pre-push.before-coordinator).
#     - in a ledger repo (COORDINATION.md at its top level) also installs a pre-commit hook that
#       runs ledger-lint.sh and refuses the commit on errors (a copy of the lint sits next to it).
#       A foreign pre-commit hook is handled like a foreign pre-push hook.
#   --protect "a b"  also set `git config coordinator.protectedBranches` so direct pushes to
#                    those branches are refused locally (pull requests only).
#   --settings       also turn on "delete branch on merge" on GitHub for the repo's origin
#                    (needs `gh` with access; this is free on every plan).
#   --tools "a b"    lean agent tool set: merge into the repo's .claude/settings.json the rules
#                    that turn off every optional tool group of scripts/agent-tools.json except
#                    the groups listed (the unit's "Tools" line; "none" keeps none). Other keys
#                    are kept; a re-run is idempotent. Commit the file through a PR so new
#                    worktrees get it. Needs python3.
#
# Hooks are local to a clone: run this again on every new machine and for every new clone.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

settings=0; force=0; protect=""; tools=""; tools_set=0; repos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --settings) settings=1; shift ;;
    --force) force=1; shift ;;
    --protect) protect="${2:?--protect needs a list}"; shift 2 ;;
    --tools) tools="${2:?--tools needs the groups to keep (or none)}"; tools_set=1; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "unknown option: $1" >&2; usage ;;
    *) repos+=("$1"); shift ;;
  esac
done
[[ ${#repos[@]} -gt 0 ]] || usage

src="$(cd "$(dirname "$0")" && pwd -P)/pre-push-guard.sh"
[[ -f "$src" ]] || { echo "guard script not found: $src" >&2; exit 1; }
marker="coordinator-kit pre-push guard"
rc=0

for repo in "${repos[@]}"; do
  printf '==> %s\n' "$repo"
  if ! common="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)"; then
    echo "    FAILED: not a git repository" >&2; rc=1; continue
  fi
  [[ "$common" == /* ]] || common="$(cd "$repo" && cd "$common" && pwd -P)"
  hooks="$(git -C "$repo" config --get core.hooksPath 2>/dev/null || true)"
  if [[ -n "$hooks" ]]; then
    [[ "$hooks" == /* ]] || hooks="$(cd "$repo" && pwd -P)/$hooks"
  else
    hooks="$common/hooks"
  fi
  mkdir -p "$hooks"
  dst="$hooks/pre-push"
  if [[ -e "$dst" ]] && ! grep -q "$marker" "$dst"; then
    if [[ $force -eq 1 ]]; then
      mv "$dst" "$dst.before-coordinator"
      echo "    existing pre-push hook saved as pre-push.before-coordinator"
    else
      echo "    FAILED: a different pre-push hook exists ($dst); rerun with --force to replace it" >&2
      rc=1; continue
    fi
  fi
  cp "$src" "$dst" && chmod +x "$dst"
  echo "    pre-push guard installed ($dst)"

  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" && -f "$top/COORDINATION.md" ]]; then
    skip_pc=0
    pc="$hooks/pre-commit"; pmarker="coordinator-kit ledger-lint pre-commit"
    if [[ -e "$pc" ]] && ! grep -q "$pmarker" "$pc"; then
      if [[ $force -eq 1 ]]; then
        mv "$pc" "$pc.before-coordinator"
        echo "    existing pre-commit hook saved as pre-commit.before-coordinator"
      else
        echo "    FAILED: a different pre-commit hook exists ($pc); rerun with --force to replace it" >&2
        rc=1; skip_pc=1
      fi
    fi
  fi
  if [[ -n "$top" && -f "$top/COORDINATION.md" && ${skip_pc:-0} -eq 0 ]]; then
    cp "$(dirname "$src")/ledger-lint.sh" "$hooks/coordinator-ledger-lint.sh"
    cat >"$pc" <<'HOOK'
#!/usr/bin/env bash
# coordinator-kit ledger-lint pre-commit: refuse a commit that breaks the ledger rules.
command -v python3 >/dev/null 2>&1 || { echo "ledger-lint skipped: python3 not found" >&2; exit 0; }
top="$(git rev-parse --show-toplevel)"
[[ -f "$top/COORDINATION.md" ]] || exit 0
exec bash "$(dirname "$0")/coordinator-ledger-lint.sh" "$top"
HOOK
    chmod +x "$pc"
    echo "    ledger-lint pre-commit installed ($pc); it holds a copy of the lint: re-run install-guards.sh after upgrading the plugin"
  fi

  if [[ -n "$protect" ]]; then
    git -C "$repo" config coordinator.protectedBranches "$protect"
    echo "    protected branches (local pushes refused): $protect"
  fi

  if [[ $tools_set -eq 1 ]]; then
    if [[ -z "$top" ]]; then
      echo "    FAILED: no work tree; agent tool settings not written" >&2; rc=1
    elif ! command -v python3 >/dev/null 2>&1; then
      echo "    FAILED: python3 not found; agent tool settings not written" >&2; rc=1
    elif out="$(python3 -I "$(dirname "$src")/lean-tools.py" "$(dirname "$src")/agent-tools.json" \
                "$top/.claude/settings.json" "$tools")"; then
      echo "    agent tools ($out): $top/.claude/settings.json keeps: $tools"
      [[ "$out" == written ]] && echo "    commit .claude/settings.json through a PR so new worktrees get it"
    else
      echo "    FAILED: agent tool settings not written" >&2; rc=1
    fi
  fi

  if [[ $settings -eq 1 ]]; then
    url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
    slug="$(printf '%s' "$url" | sed -E 's#^(https://|git@)[^/:]+[/:]##; s#\.git$##')"
    if [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && command -v gh >/dev/null 2>&1; then
      if gh repo edit "$slug" --delete-branch-on-merge >/dev/null 2>&1; then
        echo "    GitHub: delete branch on merge is on ($slug)"
      else
        echo "    WARNING: could not change GitHub settings for $slug (access?)" >&2
      fi
    else
      echo "    WARNING: no GitHub origin or no gh; settings not changed" >&2
    fi
  fi
done
exit "$rc"
