#!/usr/bin/env bash
# Point Antigravity at a released kit: a clone of this repo checked out at a release tag
# (detached, never a working copy), with Antigravity's plugin link to its plugins/coordinator.
#
#   ag-install.sh [--tag vX.Y.Z] [--dir <clone>] [--link <plugin link>] [--repo <url>] [--dry-run]
#   ag-install.sh --check [--link <plugin link>] [--repo <url>]
#
# Defaults: --dir ~/.gemini/coordinator-kit, --link ~/.gemini/config/plugins/coordinator,
# --repo https://github.com/hoanghuynh296/claude-coordinator.git, --tag the newest v* tag.
# Install: clone (first run) or fetch tags, refuse a clone with local changes, refuse a tag whose
# two manifests (plugin.json, .claude-plugin/plugin.json) do not both give its version, check out
# the tag, then repoint the link. The link must be a symlink or absent: a real folder there is
# refused (move it aside yourself). The checkout the link pointed at before is left alone.
# One line: "ag-install: <link> -> <target> at <tag> (was <old target> <old ref>)". Exit 0 done,
# 1 refused or failed, 2 usage.
# --check changes nothing: "ag-install: <link> -> <target>: <ref> (latest <tag>): ok|STALE",
# exit 0 when the target is a checkout of the newest tag, 1 otherwise (older tag, a branch, a
# working copy with changes, no link).
set -euo pipefail

dir="${COORDINATOR_AG_DIR:-$HOME/.gemini/coordinator-kit}"
link="${COORDINATOR_AG_LINK:-$HOME/.gemini/config/plugins/coordinator}"
repo="${COORDINATOR_AG_REPO:-https://github.com/hoanghuynh296/claude-coordinator.git}"
tag=""; check=0; dry=0
usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="${2:-}"; [[ -n "$tag" ]] || usage; shift 2 ;;
    --dir) dir="${2:-}"; [[ -n "$dir" ]] || usage; shift 2 ;;
    --link) link="${2:-}"; [[ -n "$link" ]] || usage; shift 2 ;;
    --repo) repo="${2:-}"; [[ -n "$repo" ]] || usage; shift 2 ;;
    --check) check=1; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
die() { echo "ag-install: $*" >&2; exit 1; }

# newest_tag <tag list on stdin>: the highest vX.Y.Z in version order (v0.12.0 after v0.9.0)
newest_tag() { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | sed 's/^/v/'; }

# where_at <checkout>: "<tag>" when HEAD is exactly a release tag and the tree is clean, else a
# description ("branch feat/x", "detached abc1234", "... with local changes")
where_at() {
  local d="$1" t b s=""
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git checkout"; return; }
  [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]] && s=" with local changes"
  b="$(git -C "$d" symbolic-ref --short -q HEAD || true)"
  if [[ -n "$b" ]]; then echo "branch $b$s"; return; fi
  t="$(git -C "$d" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 || true)"
  if [[ -n "$t" ]]; then echo "v$t$s"; else echo "detached $(git -C "$d" rev-parse --short HEAD)$s"; fi
}

old_target=""; [[ -L "$link" ]] && old_target="$(cd "$link" 2>/dev/null && pwd -P || readlink "$link")"

if (( check )); then
  latest="$(git ls-remote --tags --refs "$repo" 2>/dev/null | sed 's#.*refs/tags/##' | newest_tag || true)"
  [[ -n "$latest" ]] || die "cannot list the tags of $repo"
  if [[ ! -e "$link" ]]; then echo "ag-install: $link: missing (latest $latest): STALE"; exit 1; fi
  target="$(cd "$link" && pwd -P)"
  ref="$(where_at "$target")"
  if [[ "$ref" == "$latest" ]]; then echo "ag-install: $link -> $target: $ref (latest $latest): ok"; exit 0; fi
  echo "ag-install: $link -> $target: $ref (latest $latest): STALE"; exit 1
fi

if [[ -e "$link" && ! -L "$link" ]]; then die "$link is a real folder, not a link: move it aside, then run again"; fi

if [[ -d "$dir" ]]; then
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "$dir exists and is not a git clone"
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || die "$dir has local changes: it must be a release checkout, not a working copy"
  (( dry )) || git -C "$dir" fetch --quiet --tags --force origin || die "fetch failed in $dir"
  src="$dir"
else
  src=""
  if (( ! dry )); then git clone --quiet --no-checkout "$repo" "$dir" || die "clone of $repo failed"; src="$dir"; fi
fi

if [[ -n "$src" ]]; then
  [[ -n "$tag" ]] || tag="$(git -C "$src" tag --list 'v*' | newest_tag || true)"
  [[ -n "$tag" ]] || die "no release tag (vX.Y.Z) in $repo"
  git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no tag $tag in $repo"
  want="${tag#v}"
  for m in plugins/coordinator/plugin.json plugins/coordinator/.claude-plugin/plugin.json; do
    v="$(git -C "$src" show "$tag:$m" 2>/dev/null | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ "$v" == "$want" ]] || die "$tag: $m gives version '${v:-none}', not $want: not a release to install"
  done
else
  [[ -n "$tag" ]] || tag="<newest tag>"
fi

new_target="$dir/plugins/coordinator"
was="${old_target:-nothing}"; [[ -n "$old_target" ]] && was="$old_target $(where_at "$old_target")"
if (( dry )); then
  echo "ag-install: dry run: would check out $tag in $dir and link $link -> $new_target (was $was)"
  exit 0
fi
git -C "$dir" -c advice.detachedHead=false checkout --quiet --detach "refs/tags/$tag" || die "checkout of $tag failed in $dir"
mkdir -p "$(dirname "$link")"
ln -sfn "$new_target" "$link"
echo "ag-install: $link -> $new_target at $tag (was $was)"
