#!/usr/bin/env bash
# Bootstrap a project repo + its private coordination (ledger) repo. Idempotent: every step
# checks the current state first and is skipped when already done. Never deletes anything
# (except TEMPLATE.md, which the template asks to remove once its placeholders are filled).
#
# Usage:
#   bootstrap.sh <owner/repo> <local-dir> [options]
# Options:
#   --values FILE       KEY=VALUE lines for the template placeholders ({{KEY}}); required
#                       while TEMPLATE.md still exists in the repo
#   --plan FILE         approved plan, copied to docs/PLAN.md
#   --check NAME        extra required status check (repeatable); "changes" is always required
#   --lanes "a b c"     lane labels to create (default: "api web integrations ai platform qa")
#   --milestones "M0 M1" milestone labels + GitHub milestones (default: "M0 M1")
#   --template REPO     template repo (default: hoanghuynh296/agent-project-template)
#   --no-protect        skip branch protection (e.g. a plan without protection on private repos)
#   --ledger-only       only create/initialise the <repo>-coordination ledger (existing projects)
#
# Exits non-zero on the first failing step.
set -euo pipefail

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[[ $# -ge 2 ]] || usage
repo="$1"; local_dir="$2"; shift 2
values=""; plan=""; checks=("changes"); protect=1; ledger_only=0
lanes="api web integrations ai platform qa"
milestones="M0 M1"
template="hoanghuynh296/agent-project-template"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) values="$2"; shift 2 ;;
    --plan) plan="$2"; shift 2 ;;
    --check) checks+=("$2"); shift 2 ;;
    --lanes) lanes="$2"; shift 2 ;;
    --milestones) milestones="$2"; shift 2 ;;
    --template) template="$2"; shift 2 ;;
    --no-protect) protect=0; shift ;;
    --ledger-only) ledger_only=1; protect=0; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "repo must be owner/name" >&2; exit 2; }
for bin in gh git python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing required tool: $bin" >&2; exit 1; }
done
[[ -z "$values" || -f "$values" ]] || { echo "values file not found: $values" >&2; exit 1; }
[[ -z "$plan" || -f "$plan" ]] || { echo "plan file not found: $plan" >&2; exit 1; }
[[ -n "$values" ]] && values="$(cd "$(dirname "$values")" && pwd -P)/$(basename "$values")"
[[ -n "$plan" ]] && plan="$(cd "$(dirname "$plan")" && pwd -P)/$(basename "$plan")"

plugin_root="$(cd "$(dirname "$0")/.." && pwd -P)"
ledger_template="$plugin_root/skills/coordinator/references/templates/ledger.md"
owner="${repo%%/*}"
name="${repo##*/}"
ledger_repo="${repo}-coordination"
ledger_dir="${local_dir%/}-coordination"

step() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok: %s\n' "$*"; }
fail() { printf '    FAILED: %s\n' "$*" >&2; exit 1; }

# fill_placeholders <dir> <values-file> <file>...  (python: values may contain / & etc.)
fill_placeholders() {
  python3 -I - "$@" <<'PY'
import sys
root, values_file, files = sys.argv[1], sys.argv[2], sys.argv[3:]
vals = {}
with open(values_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v
changed = 0
for rel in files:
    path = f"{root}/{rel}"
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
        continue
    new = text
    for k, v in vals.items():
        new = new.replace("{{" + k + "}}", v)
    if new != text:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        changed += 1
print(f"    filled placeholders in {changed} file(s)")
PY
}

if [[ $ledger_only -eq 0 ]]; then
# ---------------------------------------------------------------- 1. project repo
step "1/9 project repo $repo"
if gh repo view "$repo" >/dev/null 2>&1; then
  ok "exists"
else
  gh repo create "$repo" --private --template "$template" >/dev/null || fail "gh repo create"
  ok "created from template $template"
fi
for _ in $(seq 1 30); do
  gh api "repos/$repo/branches/main" >/dev/null 2>&1 && break
  sleep 2
done
gh api "repos/$repo/branches/main" >/dev/null 2>&1 || fail "branch main not available on $repo"

# ---------------------------------------------------------------- 2. clone
step "2/9 local clone $local_dir"
if [[ -d "$local_dir/.git" ]]; then
  url="$(git -C "$local_dir" remote get-url origin)"
  [[ "$url" == *"$owner/$name"* ]] || fail "$local_dir is a clone of $url, not $repo"
  git -C "$local_dir" fetch --quiet origin || fail "git fetch"
  ok "already cloned"
else
  [[ ! -e "$local_dir" ]] || fail "$local_dir exists and is not a git clone"
  gh repo clone "$repo" "$local_dir" -- --quiet || fail "gh repo clone"
  ok "cloned"
fi

# ---------------------------------------------------------------- 3. develop branch
step "3/9 develop branch"
if git -C "$local_dir" rev-parse --verify --quiet refs/heads/develop >/dev/null; then
  git -C "$local_dir" checkout --quiet develop
  ok "local develop exists"
elif git -C "$local_dir" rev-parse --verify --quiet refs/remotes/origin/develop >/dev/null; then
  git -C "$local_dir" checkout --quiet -b develop --track origin/develop
  ok "tracking origin/develop"
else
  git -C "$local_dir" checkout --quiet -b develop origin/main
  ok "created develop from main"
fi
if [[ -n "$(git -C "$local_dir" status --porcelain)" ]]; then
  fail "working tree of $local_dir is not clean; commit or stash first"
fi

# ---------------------------------------------------------------- 4. placeholders + plan
step "4/9 template placeholders and plan"
if [[ -f "$local_dir/TEMPLATE.md" ]]; then
  [[ -n "$values" ]] || fail "TEMPLATE.md present: pass --values with the placeholders listed in it"
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(git -C "$local_dir" ls-files)
  fill_placeholders "$local_dir" "$values" "${files[@]}"
  [[ -n "$plan" ]] && cp "$plan" "$local_dir/docs/PLAN.md" && ok "plan copied to docs/PLAN.md"
  left="$(git -C "$local_dir" grep -nE '\{\{[A-Z][A-Z0-9_]*\}\}' -- . ':!TEMPLATE.md' || true)"
  if [[ -n "$left" ]]; then
    printf '%s\n' "$left" >&2
    git -C "$local_dir" checkout --quiet -- .
    fail "unfilled placeholders above (changes reverted); add them to $values"
  fi
  git -C "$local_dir" rm --quiet TEMPLATE.md
  git -C "$local_dir" add -A
  git -C "$local_dir" commit --quiet -m "chore: fill template placeholders and add plan" || fail "commit"
  ok "placeholders filled, TEMPLATE.md removed, committed"
elif [[ -n "$plan" ]] && ! cmp -s "$plan" "$local_dir/docs/PLAN.md"; then
  cp "$plan" "$local_dir/docs/PLAN.md"
  git -C "$local_dir" add docs/PLAN.md
  git -C "$local_dir" commit --quiet -m "docs: update plan" || fail "commit"
  ok "plan updated"
else
  ok "nothing to fill"
fi

# ---------------------------------------------------------------- 5. push develop
step "5/9 push develop"
git -C "$local_dir" push --quiet -u origin develop || fail "git push develop (protected already? open a PR instead)"
ok "pushed"

# ---------------------------------------------------------------- 6. repo settings
step "6/9 default branch develop + delete branch on merge"
gh repo edit "$repo" --default-branch develop --delete-branch-on-merge >/dev/null || fail "gh repo edit"
ok "set"

# ---------------------------------------------------------------- 7. labels + milestones
step "7/9 labels and milestones"
for lane in $lanes; do
  gh label create "lane:$lane" --repo "$repo" --color 1d76db --description "Lane $lane" --force >/dev/null || fail "label lane:$lane"
done
for m in $milestones; do
  gh label create "milestone:$m" --repo "$repo" --color 5319e7 --description "Milestone $m" --force >/dev/null || fail "label milestone:$m"
  if ! gh api "repos/$repo/milestones?state=all&per_page=100" --jq '.[].title' | grep -qx "$m"; then
    gh api "repos/$repo/milestones" -f title="$m" >/dev/null || fail "milestone $m"
  fi
done
gh label create decision --repo "$repo" --color d93f0b --description "Needs an owner decision" --force >/dev/null || fail "label decision"
ok "lanes: $lanes; milestones: $milestones; decision"

else
  step "ledger only: skipping steps 1-7 and 9"
fi

# ---------------------------------------------------------------- 8. ledger repo
step "8/9 ledger repo $ledger_repo -> $ledger_dir"
if ! gh repo view "$ledger_repo" >/dev/null 2>&1; then
  gh repo create "$ledger_repo" --private --description "Coordination ledger for $repo" >/dev/null || fail "create $ledger_repo"
  ok "created"
fi
if [[ ! -d "$ledger_dir/.git" ]]; then
  [[ ! -e "$ledger_dir" ]] || fail "$ledger_dir exists and is not a git clone"
  gh repo clone "$ledger_repo" "$ledger_dir" -- --quiet 2>/dev/null || fail "clone $ledger_repo"
fi
if [[ ! -f "$ledger_dir/COORDINATION.md" ]]; then
  [[ -f "$ledger_template" ]] || fail "ledger template missing: $ledger_template"
  git -C "$ledger_dir" rev-parse --verify --quiet HEAD >/dev/null || git -C "$ledger_dir" symbolic-ref HEAD refs/heads/main
  cp "$ledger_template" "$ledger_dir/COORDINATION.md"
  project_name="$name"
  if [[ -n "$values" ]]; then
    v="$(sed -n 's/^PROJECT_NAME=//p' "$values" | head -n 1)"; [[ -n "$v" ]] && project_name="$v"
  fi
  tmp_values="$(mktemp)"
  printf 'PROJECT_NAME=%s\nREPO=%s\nLEDGER_REPO=%s\nOWNER_GITHUB=%s\nDATE=%s\n' \
    "$project_name" "$repo" "$ledger_repo" "$owner" "$(date +%Y-%m-%d)" > "$tmp_values"
  fill_placeholders "$ledger_dir" "$tmp_values" COORDINATION.md
  rm -f "$tmp_values"
  mkdir -p "$ledger_dir/handover"
  # shellcheck disable=SC2016  # backticks are Markdown, not expansions
  printf '# Handover notes\n\nOne file per rotation: `YYYY-MM-DD-<session-name>.md` (template: coordinator plugin `references/templates/handover.md`).\n' > "$ledger_dir/handover/README.md"
  git -C "$ledger_dir" add -A
  git -C "$ledger_dir" commit --quiet -m "docs: initial coordination ledger" || fail "ledger commit"
  git -C "$ledger_dir" push --quiet -u origin HEAD || fail "ledger push"
  ok "COORDINATION.md + handover/ committed and pushed"
else
  ok "ledger already initialised"
fi

# ---------------------------------------------------------------- 9. branch protection
step "9/9 branch protection (required checks: ${checks[*]})"
if [[ $protect -eq 1 ]]; then
  body="$(python3 -I -c '
import json, sys
print(json.dumps({
  "required_status_checks": {"strict": False, "contexts": sys.argv[1:]},
  "enforce_admins": False,
  "required_pull_request_reviews": None,
  "restrictions": None,
  "allow_force_pushes": False,
  "allow_deletions": False,
}))' "${checks[@]}")"
  for branch in develop main; do
    printf '%s' "$body" | gh api -X PUT "repos/$repo/branches/$branch/protection" --input - >/dev/null \
      || fail "protect $branch (private repos need a paid plan; rerun with --no-protect to skip)"
    ok "$branch protected"
  done
else
  ok "skipped (--no-protect)"
fi

printf '\nDone.\n  project: %s (%s)\n  ledger:  %s (%s)\n' "$repo" "$local_dir" "$ledger_repo" "$ledger_dir"
printf '  next: register this session as coordinator with the ledger path above.\n'
