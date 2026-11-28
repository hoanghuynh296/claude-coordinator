#!/usr/bin/env bash
# ag-install.sh (#55) against a local bare origin with release tags: fresh install at the newest
# tag (version order), --tag, moving the link on a new release, --check ok / STALE (older tag,
# branch, local changes, missing link), refusals (real folder at the link, dirty clone, manifests
# that disagree with the tag, unknown tag), --dry-run changes nothing, the old checkout stays.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$root/plugins/coordinator/scripts/ag-install.sh"
w="$root/tests/.work/ag-install"; rm -rf "${w:?}"; mkdir -p "$w"
unset COORDINATOR_AG_DIR COORDINATOR_AG_LINK COORDINATOR_AG_REPO
pass=0; failn=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
has() { [[ "$3" == *"$2"* ]] && ok "$1" || bad "$1 (want: $2)" "$3"; }

# origin: tags v0.9.0, v0.10.0 (newest by version, not by text), and v0.11.0 whose manifests disagree
src="$w/src"; git init -q "$src"; git -C "$src" config user.email t@t; git -C "$src" config user.name t
mkdir -p "$src/plugins/coordinator/.claude-plugin"
release() { # <tag> <plugin.json version> <.claude-plugin version>
  printf '{\n  "name": "coordinator",\n  "version": "%s"\n}\n' "$2" >"$src/plugins/coordinator/plugin.json"
  printf '{\n  "name": "coordinator",\n  "version": "%s"\n}\n' "$3" >"$src/plugins/coordinator/.claude-plugin/plugin.json"
  git -C "$src" add -A; git -C "$src" commit -qm "$1"; git -C "$src" tag "$1"
}
release v0.9.0 0.9.0 0.9.0
release v0.10.0 0.10.0 0.10.0
git clone -q --bare "$src" "$w/origin.git"
R="$w/origin.git"; D="$w/gemini/coordinator-kit"; L="$w/gemini/config/plugins/coordinator"
run() { bash "$script" --repo "$R" --dir "$D" --link "$L" "$@" 2>&1; }

# the old install: a link to a working copy on a branch (as on the Mac mini before #55)
old="$w/old-checkout"; git clone -q "$R" "$old"; git -C "$old" checkout -qb feat/antigravity-dual-runtime
mkdir -p "$(dirname "$L")"; ln -s "$old/plugins/coordinator" "$L"

out="$(run --check)" && rc=0 || rc=$?
has "check: branch checkout is STALE" 'branch feat/antigravity-dual-runtime (latest v0.10.0): STALE' "$out"
[[ $rc -eq 1 ]] && ok "check: STALE exits 1" || bad "check exit $rc"

out="$(run --dry-run)"
has "dry run: says what it would do" 'would check out <newest tag>' "$out"
[[ ! -e "$D" && "$(readlink "$L")" == "$old/plugins/coordinator" ]] && ok "dry run: nothing cloned, link unchanged" || bad "dry run changed something"

out="$(run)"
has "install: newest tag by version" "at v0.10.0" "$out"
has "install: names the old target" "was $old/plugins/coordinator branch feat/antigravity-dual-runtime" "$out"
[[ "$(readlink "$L")" == "$D/plugins/coordinator" ]] && ok "install: link moved to the release clone" || bad "link: $(readlink "$L")"
[[ -z "$(git -C "$D" symbolic-ref -q HEAD || true)" && "$(git -C "$D" describe --tags --exact-match)" == v0.10.0 ]] && ok "install: detached at the tag" || bad "clone HEAD"
[[ "$(git -C "$old" symbolic-ref --short HEAD)" == feat/antigravity-dual-runtime ]] && ok "install: old checkout left alone" || bad "old checkout changed"
out="$(run --check)" && rc=0 || rc=$?
has "check: release checkout ok" ': v0.10.0 (latest v0.10.0): ok' "$out"
[[ $rc -eq 0 ]] && ok "check: ok exits 0" || bad "check exit $rc"

out="$(run --tag v0.9.0)"
has "--tag: older release" "at v0.9.0 (was $D/plugins/coordinator v0.10.0)" "$out"
out="$(run --check)" || true
has "check: older tag is STALE" 'v0.9.0 (latest v0.10.0): STALE' "$out"

# a new release on origin moves the link on the next run
release v0.12.0 0.12.0 0.12.0; git -C "$src" push -q "$R" HEAD:refs/heads/main --tags 2>/dev/null || git -C "$src" push -q "$R" --tags
out="$(run)"
has "new release: moves to v0.12.0" "at v0.12.0" "$out"

release v0.13.0 0.13.0 0.12.0; git -C "$src" push -q "$R" --tags
out="$(run --tag v0.13.0)" && rc=0 || rc=$?
has "refuses a tag whose manifests disagree" "gives version '0.12.0', not 0.13.0" "$out"
[[ $rc -eq 1 && "$(git -C "$D" describe --tags --exact-match)" == v0.12.0 ]] && ok "refused tag: checkout unchanged" || bad "rc $rc"
out="$(run --tag v9.9.9)" || true
has "refuses an unknown tag" "no tag v9.9.9" "$out"

echo x >"$D/stray"
out="$(run)" && rc=0 || rc=$?
has "refuses a clone with local changes" "has local changes" "$out"
[[ $rc -eq 1 ]] && ok "dirty clone exits 1" || bad "rc $rc"
out="$(run --check)" || true
has "check: local changes are STALE" 'with local changes' "$out"
rm -f "$D/stray"

rm "$L"; mkdir -p "$L"
out="$(run)" && rc=0 || rc=$?
has "refuses a real folder at the link" "is a real folder" "$out"
[[ $rc -eq 1 ]] && ok "real folder exits 1" || bad "rc $rc"
rmdir "$L"
out="$(run --check)" && rc=0 || rc=$?
has "check: missing link is STALE" "missing" "$out"
out="$(run --tag v0.12.0)"   # the newest tag, v0.13.0, is refused above
has "install: creates a missing link" "at v0.12.0 (was nothing)" "$out"
out="$(bash "$script" --bogus 2>&1)" && rc=0 || rc=$?
[[ $rc -eq 2 ]] && ok "usage error exits 2" || bad "usage rc $rc" "$out"

rm -rf "${w:?}"
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
