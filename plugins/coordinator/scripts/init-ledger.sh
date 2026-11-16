#!/usr/bin/env bash
# Create the standard ledger layout in a directory from the plugin's templates.
# Never overwrites an existing file, so it is safe on a ledger that already has content
# (use it to add the files a migration is missing). No network, no git commit.
#
# Usage: init-ledger.sh <ledger-dir> [--name "Project name"] [--owner <github-user>] [--workspace]
#
#   --name       project name for the headings (default: the directory name)
#   --owner      the owner's GitHub user (default: "the owner")
#   --workspace  multi-repo workspace: also write a .gitignore that tracks only
#                COORDINATION.md and coordination/ (unit repos live in products/)
#
# Layout written:
#   COORDINATION.md
#   coordination/{README,PROFILE,ROADMAP,DECISIONS}.md
#   coordination/handover/.gitkeep, coordination/memory/.gitkeep
set -euo pipefail

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[[ $# -ge 1 ]] || usage
dir="$1"; shift
name=""; owner="the owner"; workspace=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    --owner) owner="${2:?--owner needs a value}"; shift 2 ;;
    --workspace) workspace=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "init-ledger.sh needs python3" >&2; exit 1; }
templates="$(cd "$(dirname "$0")/.." && pwd -P)/skills/coordinator/references/templates"
[[ -d "$templates" ]] || { echo "templates not found: $templates" >&2; exit 1; }

mkdir -p "$dir/coordination/handover" "$dir/coordination/memory"
dir="$(cd "$dir" && pwd -P)"
[[ -n "$name" ]] || name="$(basename "$dir" | sed 's/-coordination$//')"
today="$(date +%Y-%m-%d)"

# put <template> <destination relative to the ledger dir>
put() {
  local src="$templates/$1" dst="$dir/$2"
  if [[ -e "$dst" ]]; then
    printf '    kept    %s\n' "$2"
    return 0
  fi
  python3 -I - "$src" "$dst" "$name" "$owner" "$today" <<'PY'
import sys
src, dst, name, owner, today = sys.argv[1:6]
with open(src, encoding="utf-8") as fh:
    text = fh.read()
text = text.replace("{{PROJECT_NAME}}", name).replace("{{OWNER}}", owner).replace("{{DATE}}", today)
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
  printf '    created %s\n' "$2"
}

printf '==> ledger layout in %s\n' "$dir"
put COORDINATION.md COORDINATION.md
put README.md coordination/README.md
put PROFILE.md coordination/PROFILE.md
put ROADMAP.md coordination/ROADMAP.md
put DECISIONS.md coordination/DECISIONS.md
for keep in coordination/handover/.gitkeep coordination/memory/.gitkeep; do
  [[ -n "$(ls -A "$dir/$(dirname "$keep")" 2>/dev/null)" ]] || : > "$dir/$keep"
done

if [[ $workspace -eq 1 ]]; then
  if [[ -e "$dir/.gitignore" ]]; then
    printf '    kept    .gitignore\n'
  else
    printf '%s\n' \
      '# Coordination workspace: only the ledger is tracked here.' \
      '# Unit repos are separate git repos under products/.' \
      '/*' '!/.gitignore' '!/COORDINATION.md' '!/coordination/' > "$dir/.gitignore"
    printf '    created .gitignore\n'
  fi
fi

printf 'next: fill coordination/PROFILE.md (see the skill, references/profile.md), then run ledger-lint.sh.\n'
