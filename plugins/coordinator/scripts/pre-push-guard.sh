#!/usr/bin/env bash
# coordinator-kit pre-push guard (installed as .git/hooks/pre-push by install-guards.sh).
#
# Refuses a push when:
#   1. the branch being pushed already had its pull request merged or closed and has no open
#      one: commits added there go nowhere. Cut a new branch from the integration branch.
#   2. the branch is listed in `git config coordinator.protectedBranches` (space-separated,
#      e.g. "main master"): those are changed through pull requests only.
#
# Fails open: without `gh`, without network or without access to the repo it warns and lets
# the push through. Deleting a branch is never blocked. Override once with
# `git push --no-verify` (say why in your report).
set -u

remote="${1:-origin}"
protected="$(git config --get coordinator.protectedBranches 2>/dev/null || true)"
zero="0000000000000000000000000000000000000000"
status=0

while read -r local_ref local_sha remote_ref _remote_sha; do
  [[ -z "${remote_ref:-}" ]] && continue
  [[ "$local_sha" == "$zero" ]] && continue          # deleting a remote branch
  [[ "$remote_ref" == refs/heads/* ]] || continue    # tags and other refs
  branch="${remote_ref#refs/heads/}"

  for p in $protected; do
    if [[ "$branch" == "$p" ]]; then
      echo "pre-push guard: '$branch' is a protected branch here; open a pull request instead." >&2
      status=1
      continue 2
    fi
  done

  command -v gh >/dev/null 2>&1 || { echo "pre-push guard: gh not found, skipping the merged-PR check for '$branch'." >&2; continue; }
  if ! states="$(gh pr list --head "$branch" --state all --limit 20 --json number,state \
                  --jq '.[] | "\(.state) \(.number)"' 2>/dev/null)"; then
    echo "pre-push guard: could not query pull requests for '$branch' (auth or network); push allowed." >&2
    continue
  fi
  [[ -z "$states" ]] && continue                      # no PR yet: a new branch
  grep -q '^OPEN ' <<<"$states" && continue           # an open PR: normal work
  last="$(head -n 1 <<<"$states")"
  echo "pre-push guard: the pull request of '$branch' is already ${last%% *} (#${last##* }) and no PR is open for it." >&2
  echo "  Commits pushed here would be lost. Cut a new branch from the integration branch and open a new PR:" >&2
  echo "    git fetch $remote && git switch -c <new-branch> $remote/<integration> && git cherry-pick <your new commits>" >&2
  echo "  Override (rare, e.g. reusing a branch name on purpose): git push --no-verify" >&2
  status=1
done

exit "$status"
