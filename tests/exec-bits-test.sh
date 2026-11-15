#!/usr/bin/env bash
# Fail if any tracked *.sh under plugins/ is not executable in git (mode 100755).
# Commands run scripts with `bash <path>`, but users and hooks may call them directly.
set -euo pipefail
cd "$(dirname "$0")/.."
bad="$(git ls-files -s -- 'plugins/*.sh' 'plugins/**/*.sh' | awk '$1 != "100755" {print $1, $4}')"
count="$(git ls-files -- 'plugins/*.sh' 'plugins/**/*.sh' | wc -l | tr -d ' ')"
if [[ -n "$bad" ]]; then
  echo "FAIL: not executable in git (fix: git update-index --chmod=+x <file>):"
  echo "$bad"
  exit 1
fi
echo "PASS: all $count tracked plugin *.sh files are 100755"
