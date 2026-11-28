#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # expect() evals single-quoted conditions later
# End-to-end bootstrap run against local bare repos and a fake `gh` (no network, no GitHub).
# Checks: placeholders filled + TEMPLATE.md removed on develop, develop pushed, ledger created in the
# standard layout and lint-clean,
# branch protection 403 ("Upgrade to GitHub Pro") -> warning + continue, exit 0; rerun idempotent;
# required checks = the jobs of the repo's ci.yml (never `changes`) plus --check, and a removed lane
# is dropped on the next run.
# Usage: tests/bootstrap-test.sh [template-dir]  (default: ../agent-project-template next to this repo)
# Without a template checkout (CI: the template is private) it builds a minimal template with the
# same fast-CI lane jobs and runs the same checks against it.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
tpl="${1:-$root/../agent-project-template}"
w="$root/tests/.work/bootstrap"; rm -rf "${w:?}"; mkdir -p "$w/bin" "$w/remotes/fakeowner"
if [[ -f "$tpl/TEMPLATE.md" ]]; then
  echo "template: $tpl ($(git -C "$tpl" log -1 --format='%h %s'))"
else
  echo "template: none at $tpl, using a minimal fast-CI template"
  tpl="$w/mini-template"; mkdir -p "$tpl/.github/workflows" "$tpl/docs"
  printf '# Template\n\nFill {{PROJECT_NAME}} and {{API_DIR}}, then delete this file.\n' > "$tpl/TEMPLATE.md"
  printf '# {{PROJECT_NAME}}\n' > "$tpl/README.md"
  : > "$tpl/docs/.gitkeep"
  {
    printf 'name: CI\non:\n  pull_request:\njobs:\n'
    for lane in api web integrations ai; do
      printf '  %s:\n    runs-on: [self-hosted, ci]\n    steps:\n      - name: %s CI needed?\n' "$lane" "$lane"
      printf "        run: bash .github/scripts/ci-needed.sh %s '{{API_DIR}}/**'\n\n" "$lane"
    done
    printf '  e2e:\n    strategy:\n      matrix:\n        os: [a, b]\n    runs-on: [self-hosted, ci]\n    steps:\n      - run: true\n'
  } > "$tpl/.github/workflows/ci.yml"
  git -C "$tpl" init -q -b main && git -C "$tpl" add -A && git -C "$tpl" commit -qm template
fi
lanes_expected="api web integrations ai"  # the template's fast-CI lane jobs

git clone -q --bare "$tpl" "$w/remotes/fakeowner/fakerepo.git"
git -C "$w/remotes/fakeowner/fakerepo.git" symbolic-ref HEAD refs/heads/main
git init -q --bare -b main "$w/remotes/fakeowner/fakerepo-coordination.git"

cat > "$w/bin/gh" <<GH
#!/usr/bin/env bash
case "\$1 \$2" in
  "repo view") exit 0 ;;
  "repo clone") git clone -q "$w/remotes/\$3.git" "\$4"; exit ;;
  "repo edit"|"repo create"|"label create") exit 0 ;;
esac
if [[ "\$1" == api ]]; then
  case "\$*" in
    *"-X PUT"*protection*)
      if [[ "\${FAKE_PROTECT:-403}" == ok ]]; then
        { echo "\$*"; cat; echo; } >> "$w/protect.log"; exit 0
      fi
      echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1 ;;
    *) exit 0 ;;
  esac
fi
echo "fake gh: unhandled \$*" >&2; exit 1
GH
chmod +x "$w/bin/gh"

keys="$(git -C "$tpl" grep -ohE '\{\{[A-Z][A-Z0-9_]*\}\}' -- . ':!TEMPLATE.md' | sort -u | tr -d '{}')"
for k in $keys; do echo "$k=x_$k"; done > "$w/values.env"
sed -i '' 's/^API_DIR=.*/API_DIR=apps\/api/' "$w/values.env" 2>/dev/null || sed -i 's/^API_DIR=.*/API_DIR=apps\/api/' "$w/values.env"
printf '# Demo - Plan\n\nApproved.\n' > "$w/PLAN.md"

run() { PATH="$w/bin:$PATH" bash "$root/plugins/coordinator/scripts/bootstrap.sh" fakeowner/fakerepo "$w/fakerepo" \
  --values "$w/values.env" --plan "$w/PLAN.md" "$@" 2>&1; }
# contexts <branch>: the required checks the last protection PUT for <branch> sent, space-separated.
contexts() { python3 -I - "$w/protect.log" "$1" <<'PY'
import json, sys
log, branch = sys.argv[1], sys.argv[2]
lines, ctx = open(log, encoding="utf-8").read().splitlines(), None
for i, line in enumerate(lines):
    if f"branches/{branch}/protection" in line:
        ctx = json.loads(lines[i + 1])["required_status_checks"]["contexts"]
print(" ".join(ctx or []))
PY
}
fails=0
expect() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }

rc1=0; out1="$(run)" || rc1=$?
echo "$out1" | grep -E '^==>|WARNING|ACTION|Done' | sed 's/^/  | /'
remote="$w/remotes/fakeowner/fakerepo.git"
expect "first run exits 0" '[[ $rc1 -eq 0 ]]'
expect "403 warned, not fatal" 'echo "$out1" | grep -q "Upgrade to GitHub Pro"'
expect "owner decision line printed" 'echo "$out1" | grep -q "Record an owner decision in the ledger"'
expect "develop pushed" 'git -C "$remote" rev-parse -q --verify refs/heads/develop >/dev/null'
expect "TEMPLATE.md removed on develop" '! git -C "$remote" cat-file -e develop:TEMPLATE.md 2>/dev/null'
expect "no placeholders left on develop" '! git -C "$remote" grep -qE "\{\{[A-Z][A-Z0-9_]*\}\}" develop -- .'
expect "ci.yml paths-filter filled" 'git -C "$remote" show develop:.github/workflows/ci.yml | grep -q "apps/api/\*\*"'
expect "plan committed" 'git -C "$remote" show develop:docs/PLAN.md | grep -q Approved'
led="$w/remotes/fakeowner/fakerepo-coordination.git"
expect "ledger pushed" 'git -C "$led" cat-file -e HEAD:COORDINATION.md'
expect "ledger standard files" 'for f in README PROFILE ROADMAP DECISIONS; do git -C "$led" cat-file -e "HEAD:coordination/$f.md" || exit 1; done'
expect "ledger README names the repo" 'git -C "$led" show HEAD:coordination/README.md | grep -q "fakeowner/fakerepo"'
expect "ledger has no placeholder left" '! git -C "$led" grep -qE "\{\{[A-Z][A-Z0-9_]*\}\}" HEAD -- .'
expect "ledger handover dir" 'git -C "$led" cat-file -e HEAD:coordination/handover/.gitkeep'
expect "fresh ledger passes the lint" 'bash "$root/plugins/coordinator/scripts/ledger-lint.sh" "$w/fakerepo-coordination" >/dev/null'

rc2=0; out2="$(run)" || rc2=$?
expect "rerun exits 0 (idempotent)" '[[ $rc2 -eq 0 ]]'
expect "rerun skips fill" 'echo "$out2" | grep -q "nothing to fill"'
expect "rerun keeps ledger" 'echo "$out2" | grep -q "ledger already initialised"'
expect "required checks are the ci.yml lane jobs" 'echo "$out1" | grep -qF "required checks: $lanes_expected)"'
expect "changes is not required" '! echo "$out1" | grep "required checks:" | grep -qw changes'
if git -C "$w/fakerepo" show HEAD:.github/workflows/ci.yml | grep -q "^  e2e:"; then
  expect "matrix job skipped with a warning" 'echo "$out1" | grep -q "WARNING: skipped job e2e"'
fi

# Protection works (public repo or paid plan): drop the ai lane, rerun with an extra --check.
python3 -I - "$w/fakerepo/.github/workflows/ci.yml" <<'PY'
import re, sys
path = sys.argv[1]
lines, out, skip = open(path, encoding="utf-8").read().splitlines(), [], False
for line in lines:
    if re.match(r"  [A-Za-z0-9_-]+:", line):
        skip = line.startswith("  ai:")
    if not skip:
        out.append(line)
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
git -C "$w/fakerepo" commit -qam "ci: remove the ai lane"
rc3=0; out3="$(FAKE_PROTECT=ok run --check extra-check --check api)" || rc3=$?
want="${lanes_expected% ai} extra-check"
expect "protected run exits 0" '[[ $rc3 -eq 0 ]]'
expect "develop requires the remaining lanes + --check" '[[ "$(contexts develop)" == "$want" ]]'
expect "main requires the same checks" '[[ "$(contexts main)" == "$want" ]]'
expect "no owner decision line when protected" '! echo "$out3" | grep -q "Record an owner decision"'

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "failed: $fails"
[[ $fails -eq 0 ]]
