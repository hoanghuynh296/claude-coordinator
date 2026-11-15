#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # expect() evals single-quoted conditions later
# End-to-end bootstrap run against local bare repos and a fake `gh` (no network, no GitHub).
# Checks: placeholders filled + TEMPLATE.md removed on develop, develop pushed, ledger created,
# branch protection 403 ("Upgrade to GitHub Pro") -> warning + continue, exit 0; rerun idempotent.
# Usage: tests/bootstrap-test.sh [template-dir]  (default: ../agent-project-template next to this repo)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
tpl="${1:-$root/../agent-project-template}"
[[ -f "$tpl/TEMPLATE.md" ]] || { echo "SKIP: template checkout with TEMPLATE.md not found at $tpl"; exit 0; }
w="$root/tests/.work/bootstrap"; rm -rf "${w:?}"; mkdir -p "$w/bin" "$w/remotes/fakeowner"

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
    *"-X PUT"*protection*) echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1 ;;
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
  --values "$w/values.env" --plan "$w/PLAN.md" 2>&1; }
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
expect "ledger pushed" 'git -C "$w/remotes/fakeowner/fakerepo-coordination.git" show HEAD:COORDINATION.md | grep -q "fakeowner/fakerepo"'
expect "ledger handover dir" 'git -C "$w/remotes/fakeowner/fakerepo-coordination.git" cat-file -e HEAD:handover/README.md'

rc2=0; out2="$(run)" || rc2=$?
expect "rerun exits 0 (idempotent)" '[[ $rc2 -eq 0 ]]'
expect "rerun skips fill" 'echo "$out2" | grep -q "nothing to fill"'
expect "rerun keeps ledger" 'echo "$out2" | grep -q "ledger already initialised"'

[[ -n "${KEEP:-}" ]] || rm -rf "${w:?}"
echo "failed: $fails"
[[ $fails -eq 0 ]]
