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
#   --check NAME        extra required status check (repeatable). By default the required checks
#                       are the jobs of the new repo's .github/workflows/ci.yml (the lanes left
#                       after unused ones are removed); after removing a lane, rerun to update them
#   --lanes "a b c"     lane labels to create (default: "api web integrations ai platform qa")
#   --milestones "M0 M1" milestone labels + GitHub milestones (default: "M0 M1")
#   --template REPO     template repo (default: hoanghuynh296/agent-project-template)
#   --no-protect        skip branch protection (e.g. a plan without protection on private repos)
#   --ledger-only       only create/initialise the <repo>-coordination ledger in the standard
#                       layout (existing projects; see init-ledger.sh)
#   --dry-run           print every gh/git action it would take; reads state, changes nothing
#
# Exits non-zero on the first failing step.
set -euo pipefail

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[[ $# -ge 2 ]] || usage
repo="$1"; local_dir="$2"; shift 2
values=""; plan=""; extra_checks=(); protect=1; ledger_only=0; dry=0
lanes="api web integrations ai platform qa"
milestones="M0 M1"
template="hoanghuynh296/agent-project-template"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) values="$2"; shift 2 ;;
    --plan) plan="$2"; shift 2 ;;
    --check) extra_checks+=("$2"); shift 2 ;;
    --lanes) lanes="$2"; shift 2 ;;
    --milestones) milestones="$2"; shift 2 ;;
    --template) template="$2"; shift 2 ;;
    --no-protect) protect=0; shift ;;
    --ledger-only) ledger_only=1; protect=0; shift ;;
    --dry-run) dry=1; shift ;;
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
init_ledger="$plugin_root/scripts/init-ledger.sh"
owner="${repo%%/*}"
name="${repo##*/}"
ledger_repo="${repo}-coordination"
ledger_dir="${local_dir%/}-coordination"

step() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok: %s\n' "$*"; }
fail() { printf '    FAILED: %s\n' "$*" >&2; exit 1; }
warn() { printf '    WARNING: %s\n' "$*" >&2; }

# act <command...>: run a state-changing command (quiet), or print it in --dry-run.
act() {
  if [[ $dry -eq 1 ]]; then
    printf '    would run:'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  "$@" >/dev/null
}

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

[[ $dry -eq 1 ]] && printf 'DRY RUN: reading state only; nothing will be created or changed.\n'

if [[ $ledger_only -eq 0 ]]; then
# ---------------------------------------------------------------- 1. project repo
step "1/9 project repo $repo"
repo_new=0
if gh repo view "$repo" >/dev/null 2>&1; then
  ok "exists"
else
  act gh repo create "$repo" --private --template "$template" || fail "gh repo create"
  repo_new=1
  ok "created from template $template"
fi
if [[ $dry -eq 0 ]]; then
  for _ in $(seq 1 30); do
    gh api "repos/$repo/branches/main" >/dev/null 2>&1 && break
    sleep 2
  done
  gh api "repos/$repo/branches/main" >/dev/null 2>&1 || fail "branch main not available on $repo"
fi

# ---------------------------------------------------------------- 2. clone
step "2/9 local clone $local_dir"
have_clone=0
if [[ -d "$local_dir/.git" ]]; then
  url="$(git -C "$local_dir" remote get-url origin)"
  [[ "$url" == *"$owner/$name"* ]] || fail "$local_dir is a clone of $url, not $repo"
  act git -C "$local_dir" fetch --quiet origin || fail "git fetch"
  have_clone=1
  ok "already cloned"
else
  [[ ! -e "$local_dir" ]] || fail "$local_dir exists and is not a git clone"
  act gh repo clone "$repo" "$local_dir" -- --quiet || fail "gh repo clone"
  [[ $dry -eq 0 ]] && have_clone=1
  ok "cloned"
fi

# ---------------------------------------------------------------- 3. develop branch
step "3/9 develop branch"
if [[ $have_clone -eq 0 ]]; then
  act git -C "$local_dir" checkout --quiet -b develop origin/main
  ok "would create develop from main (no clone yet)"
elif git -C "$local_dir" rev-parse --verify --quiet refs/heads/develop >/dev/null; then
  act git -C "$local_dir" checkout --quiet develop
  ok "local develop exists"
elif git -C "$local_dir" rev-parse --verify --quiet refs/remotes/origin/develop >/dev/null; then
  act git -C "$local_dir" checkout --quiet -b develop --track origin/develop
  ok "tracking origin/develop"
else
  act git -C "$local_dir" checkout --quiet -b develop origin/main
  ok "created develop from main"
fi
if [[ $have_clone -eq 1 && -n "$(git -C "$local_dir" status --porcelain)" ]]; then
  fail "working tree of $local_dir is not clean; commit or stash first"
fi

# ---------------------------------------------------------------- 4. placeholders + plan
step "4/9 template placeholders and plan"
if [[ $have_clone -eq 0 || -f "$local_dir/TEMPLATE.md" ]]; then
  [[ -n "$values" ]] || fail "TEMPLATE.md present: pass --values with the placeholders listed in it"
  if [[ $dry -eq 1 ]]; then
    printf '    would fill {{KEY}} placeholders from %s in every tracked file, fail if any remain\n' "$values"
    [[ -n "$plan" ]] && printf '    would copy %s to docs/PLAN.md\n' "$plan"
    act git -C "$local_dir" rm --quiet TEMPLATE.md
    act git -C "$local_dir" commit --quiet -m "chore: fill template placeholders and add plan"
  else
    files=()
    while IFS= read -r f; do [[ "$f" == TEMPLATE.md ]] || files+=("$f"); done < <(git -C "$local_dir" ls-files)
    fill_placeholders "$local_dir" "$values" "${files[@]}"
    [[ -n "$plan" ]] && cp "$plan" "$local_dir/docs/PLAN.md" && ok "plan copied to docs/PLAN.md"
    left="$(git -C "$local_dir" grep -nE '\{\{[A-Z][A-Z0-9_]*\}\}' -- . ':!TEMPLATE.md' || true)"
    if [[ -n "$left" ]]; then
      printf '%s\n' "$left" >&2
      git -C "$local_dir" checkout --quiet -- .
      fail "unfilled placeholders above (changes reverted); add them to $values"
    fi
    git -C "$local_dir" rm --quiet -f TEMPLATE.md || fail "git rm TEMPLATE.md"
    git -C "$local_dir" add -A
    git -C "$local_dir" commit --quiet -m "chore: fill template placeholders and add plan" || fail "commit"
  fi
  ok "placeholders filled, TEMPLATE.md removed, committed"
elif [[ -n "$plan" ]] && ! cmp -s "$plan" "$local_dir/docs/PLAN.md"; then
  [[ $dry -eq 1 ]] && printf '    would copy %s to docs/PLAN.md\n' "$plan"
  [[ $dry -eq 0 ]] && cp "$plan" "$local_dir/docs/PLAN.md"
  act git -C "$local_dir" add docs/PLAN.md
  act git -C "$local_dir" commit --quiet -m "docs: update plan" || fail "commit"
  ok "plan updated"
else
  ok "nothing to fill"
fi

# ---------------------------------------------------------------- 5. push develop
step "5/9 push develop"
act git -C "$local_dir" push --quiet -u origin develop || fail "git push develop (protected already? open a PR instead)"
ok "pushed"

# ---------------------------------------------------------------- 6. repo settings
step "6/9 default branch develop + delete branch on merge"
act gh repo edit "$repo" --default-branch develop --delete-branch-on-merge || fail "gh repo edit"
ok "set"

# ---------------------------------------------------------------- 7. labels + milestones
step "7/9 labels and milestones"
for lane in $lanes; do
  act gh label create "lane:$lane" --repo "$repo" --color 1d76db --description "Lane $lane" --force || fail "label lane:$lane"
done
existing=""
[[ $repo_new -eq 0 ]] && existing="$(gh api "repos/$repo/milestones?state=all&per_page=100" --jq '.[].title' 2>/dev/null || true)"
for m in $milestones; do
  act gh label create "milestone:$m" --repo "$repo" --color 5319e7 --description "Milestone $m" --force || fail "label milestone:$m"
  if ! printf '%s\n' "$existing" | grep -qx "$m"; then
    act gh api "repos/$repo/milestones" -f title="$m" || fail "milestone $m"
  fi
done
act gh label create decision --repo "$repo" --color d93f0b --description "Needs an owner decision" --force || fail "label decision"
ok "lanes: $lanes; milestones: $milestones; decision"

else
  step "ledger only: skipping steps 1-7 and 9"
fi

# ---------------------------------------------------------------- 8. ledger repo
step "8/9 ledger repo $ledger_repo -> $ledger_dir"
if gh repo view "$ledger_repo" >/dev/null 2>&1; then
  ok "repo exists"
else
  act gh repo create "$ledger_repo" --private --description "Coordination ledger for $repo" || fail "create $ledger_repo"
  ok "created"
fi
ledger_clone=1
if [[ ! -d "$ledger_dir/.git" ]]; then
  [[ ! -e "$ledger_dir" ]] || fail "$ledger_dir exists and is not a git clone"
  act gh repo clone "$ledger_repo" "$ledger_dir" -- --quiet || fail "clone $ledger_repo"
  [[ $dry -eq 1 ]] && ledger_clone=0
fi
if [[ $ledger_clone -eq 0 || ! -f "$ledger_dir/COORDINATION.md" ]]; then
  [[ -f "$init_ledger" ]] || fail "init-ledger.sh missing: $init_ledger"
  if [[ $dry -eq 1 ]]; then
    printf '    would write the standard ledger layout (COORDINATION.md, coordination/{README,PROFILE,ROADMAP,DECISIONS}.md, handover/, memory/)\n'
    act git -C "$ledger_dir" commit --quiet -m "docs: initial coordination ledger"
    act git -C "$ledger_dir" push --quiet -u origin HEAD
  else
    git -C "$ledger_dir" rev-parse --verify --quiet HEAD >/dev/null || git -C "$ledger_dir" symbolic-ref HEAD refs/heads/main
    project_name="$name"
    if [[ -n "$values" ]]; then
      v="$(sed -n 's/^PROJECT_NAME=//p' "$values" | head -n 1)"; [[ -n "$v" ]] && project_name="$v"
    fi
    bash "$init_ledger" "$ledger_dir" --name "$project_name" --owner "$owner" >/dev/null || fail "init-ledger"
    # Fill the one row the script knows: the project repo itself.
    python3 -I - "$ledger_dir/coordination/README.md" "$name" "$repo" <<'PY2'
import sys
path, name, repo = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()
row = f"| {name} | `../{name}` | https://github.com/{repo} | develop / main |"
lines = [row if line.startswith("| <unit> |") else line for line in lines]
with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PY2
    git -C "$ledger_dir" add -A
    git -C "$ledger_dir" commit --quiet -m "docs: initial coordination ledger" || fail "ledger commit"
    git -C "$ledger_dir" push --quiet -u origin HEAD || fail "ledger push"
  fi
  ok "standard ledger layout committed and pushed"
else
  ok "ledger already initialised"
fi

# ---------------------------------------------------------------- 9. branch protection
# Required checks: every job of the repo's ci.yml (each lane job always reports a status, even
# when it skips; group standard ci-runners.md "Fast CI") plus --check names. Read from the
# workflow, not a fixed list, so a removed lane is never required.
ci_jobs() {
  python3 -I - "$1" <<'PY3'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
out, in_jobs, indent, job, job_indent = [], False, None, None, None
for line in lines:
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if not in_jobs:
        in_jobs = re.match(r"jobs:\s*(#.*)?$", line) is not None
        continue
    lead = len(line) - len(line.lstrip(" "))
    if lead == 0:
        break
    if indent is None:
        indent = lead
    m = re.match(r"([A-Za-z0-9_-]+):\s*(#.*)?$", line[lead:])
    if lead == indent and m:
        job, job_indent = [m.group(1), None, False], None
        out.append(job)
    elif job and lead > indent:
        job_indent = job_indent or lead
        if lead != job_indent:
            continue
        n = re.match(r"name:\s*(.+?)\s*(#.*)?$", line[lead:])
        if n:
            job[1] = n.group(1).strip("'\"")
        if re.match(r"strategy:", line[lead:]):
            job[2] = True
for jid, name, matrix in out:
    if matrix or (name and "${{" in name):
        # GitHub names these checks per matrix value ("job (x)"): not derivable here.
        print(f"skipped job {jid} (matrix or expression name): add its checks with --check", file=sys.stderr)
        continue
    print(name or jid)
PY3
}
checks=()
ci_file="$local_dir/.github/workflows/ci.yml"
if [[ $protect -eq 1 ]]; then
  if [[ -f "$ci_file" ]]; then
    skipped_log="$(mktemp)"
    jobs_out="$(ci_jobs "$ci_file" 2>"$skipped_log")" || { cat "$skipped_log" >&2; rm -f "$skipped_log"; fail "read jobs from $ci_file"; }
    while IFS= read -r c; do [[ -n "$c" ]] && warn "$c"; done < "$skipped_log"
    rm -f "$skipped_log"
    while IFS= read -r c; do [[ -n "$c" ]] && checks+=("$c"); done <<< "$jobs_out"
    [[ ${#checks[@]} -gt 0 ]] || warn "no jobs found in $ci_file"
  elif [[ $dry -eq 1 ]]; then
    printf '    would require the jobs of %s (not cloned yet)\n' "$ci_file"
  else
    warn "$ci_file not found: requiring only --check names"
  fi
fi
for c in ${extra_checks[@]+"${extra_checks[@]}"}; do
  printf '%s\n' ${checks[@]+"${checks[@]}"} | grep -qxF -- "$c" || checks+=("$c")
done
step "9/9 branch protection (required checks: ${checks[*]:-none})"
protection_skipped=""
if [[ $protect -eq 1 ]]; then
  body="$(python3 -I -c '
import json, sys
print(json.dumps({
  "required_status_checks": {"strict": False, "contexts": sys.argv[1:]} if sys.argv[1:] else None,
  "enforce_admins": False,
  "required_pull_request_reviews": None,
  "restrictions": None,
  "allow_force_pushes": False,
  "allow_deletions": False,
}))' ${checks[@]+"${checks[@]}"})"
  for branch in develop main; do
    if [[ $dry -eq 1 ]]; then
      printf '    would run: gh api -X PUT repos/%s/branches/%s/protection --input <%s>\n' "$repo" "$branch" "$body"
      continue
    fi
    if out="$(printf '%s' "$body" | gh api -X PUT "repos/$repo/branches/$branch/protection" --input - 2>&1)"; then
      ok "$branch protected"
    elif printf '%s' "$out" | grep -qiE 'upgrade to github pro|HTTP 403'; then
      warn "GitHub refused branch protection for $branch (private repo on a free plan: 'Upgrade to GitHub Pro')."
      protection_skipped="plan"
      break
    else
      printf '%s\n' "$out" >&2
      fail "protect $branch"
    fi
  done
else
  ok "skipped (--no-protect)"
  protection_skipped="flag"
fi

printf '\nDone%s.\n  project: %s (%s)\n  ledger:  %s (%s)\n' "$([[ $dry -eq 1 ]] && echo ' (dry run, nothing changed)')" "$repo" "$local_dir" "$ledger_repo" "$ledger_dir"
if [[ "$protection_skipped" == "plan" ]]; then
  printf '  ACTION: branch protection is OFF (plan limit). Record an owner decision in the ledger\n'
  printf '          (C-xxx: upgrade plan / make repo public / accept no protection) and rerun after a change.\n'
fi
printf '  next: fill coordination/PROFILE.md in the ledger, then register this session as coordinator.\n'
