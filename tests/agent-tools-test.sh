#!/usr/bin/env bash
# install-guards.sh --tools: writes the lean agent tool set into a repo's .claude/settings.json,
# keeps every key it does not own, is idempotent, switches groups back on, refuses unknown
# groups and broken JSON without writing, and the catalog never turns off a tool agents need.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scripts="$root/plugins/coordinator/scripts"
w="$root/tests/.work/agent-tools"; rm -rf "${w:?}"; mkdir -p "$w"
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; }
# check <name> <python expression over s (the settings dict)>
check() {
  if python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' \
      "$w/repo/.claude/settings.json" "$2" 2>/dev/null; then ok "$1"; else bad "$1"; fi
}
guards() { bash "$scripts/install-guards.sh" "$@" "$w/repo" 2>&1; }

git init -q -b main "$w/repo"
git -C "$w/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
cfg="$w/repo/.claude/settings.json"

echo "--- fresh repo, keep browser and semi-design"
out="$(guards --tools "browser semi-design")"
[[ "$out" == *"agent tools (written)"* ]] && ok "settings written" || bad "settings written: $out"
check "computer-use denied"           "'mcp__computer-use' in s['permissions']['deny']"
check "Artifact tool denied"          "'Artifact' in s['permissions']['deny']"
check "kept browser not denied"       "'mcp__Claude_Browser' not in s['permissions']['deny']"
check "cloudflare skill off"          "s['skillOverrides']['cloudflare:wrangler'] == 'off'"
check "office skill off"              "s['skillOverrides']['anthropic-skills:docx'] == 'off'"
check "kept browser skill on"         "'anthropic-skills:built-in-browser' not in s['skillOverrides']"
check "kept semi-design not disabled" "'enabledPlugins' not in s"
check "connectors off"                "s['disableClaudeAiConnectors'] is True"

echo "--- re-run is idempotent"
cp "$cfg" "$w/first.json"
out="$(guards --tools "browser semi-design")"
[[ "$out" == *"agent tools (unchanged)"* ]] && ok "re-run reports unchanged" || bad "re-run: $out"
cmp -s "$cfg" "$w/first.json" && ok "re-run leaves the file byte-identical" || bad "re-run changed the file"

echo "--- existing settings are merged, never overwritten"
cat > "$cfg" <<'JSON'
{
  "model": "opus",
  "hooks": {"Stop": []},
  "permissions": {"allow": ["Bash(npm test)"], "deny": ["Bash(rm -rf *)", "mcp__Claude_Browser"]},
  "skillOverrides": {"my-skill": "name-only", "cloudflare:wrangler": "name-only"},
  "enabledPlugins": {"foo@bar": true}
}
JSON
guards --tools "semi-design" >/dev/null
check "unrelated keys kept"           "s['model'] == 'opus' and s['hooks'] == {'Stop': []}"
check "allow rules kept"              "s['permissions']['allow'] == ['Bash(npm test)']"
check "own deny rule kept first"      "s['permissions']['deny'][0] == 'Bash(rm -rf *)'"
check "no duplicate deny rules"       "len(s['permissions']['deny']) == len(set(s['permissions']['deny']))"
check "browser now denied"            "'mcp__Claude_Browser' in s['permissions']['deny']"
check "own skill override kept"       "s['skillOverrides']['my-skill'] == 'name-only'"
check "listed skill set off"          "s['skillOverrides']['cloudflare:wrangler'] == 'off'"
check "own plugin kept"               "s['enabledPlugins'] == {'foo@bar': True}"
cp "$cfg" "$w/merged.json"
guards --tools "semi-design" >/dev/null
cmp -s "$cfg" "$w/merged.json" && ok "merged file is stable on re-run" || bad "merged file changed on re-run"

echo "--- keeping a group switches it back on"
guards --tools "semi-design cloudflare browser connectors" >/dev/null
check "cloudflare server allowed"     "'mcp__plugin_cloudflare_cloudflare' not in s['permissions']['deny']"
check "cloudflare skill on"           "'cloudflare:wrangler' not in s['skillOverrides']"
check "browser allowed again"         "'mcp__Claude_Browser' not in s['permissions']['deny']"
check "connectors on again"           "'disableClaudeAiConnectors' not in s"
check "own rule still there"          "'Bash(rm -rf *)' in s['permissions']['deny']"
guards --tools none >/dev/null
check "none: semi-design plugin off"  "s['enabledPlugins']['semi-design@semi-marketplace'] is False and s['enabledPlugins']['foo@bar'] is True"

echo "--- refusals write nothing"
cp "$cfg" "$w/before.json"
if guards --tools "browser nosuch" >/dev/null; then bad "unknown group accepted"; else ok "unknown group refused"; fi
cmp -s "$cfg" "$w/before.json" && ok "unknown group: file untouched" || bad "unknown group changed the file"
printf '{ not json' > "$cfg"
if guards --tools none >/dev/null; then bad "broken JSON accepted"; else ok "broken JSON refused"; fi
[[ "$(cat "$cfg")" == "{ not json" ]] && ok "broken JSON: file untouched" || bad "broken JSON overwritten"
rm -f "$cfg"
guards >/dev/null
[[ ! -e "$cfg" ]] && ok "without --tools no settings file" || bad "settings written without --tools"

echo "--- catalog never turns off what agents need"
python3 -I - "$scripts/agent-tools.json" <<'PY' && ok "catalog groups are well formed and spare core tools" || bad "catalog"
import json, sys
groups = json.load(open(sys.argv[1]))["groups"]
core = ("Bash", "Read", "Edit", "Write", "Agent", "SendMessage", "Skill", "ToolSearch", "mcp__ccd_")
fields = ("deny", "skillsOff", "pluginsOff", "settingsOn")
for name, g in groups.items():
    assert g.get("why"), name + " has no why"
    assert any(g.get(f) for f in fields), name + " turns nothing off"
    assert set(g) <= set(fields) | {"why"}, name + " has an unknown field"
    for rule in g.get("deny", []):
        assert "(" not in rule and "*" not in rule, rule + " is not a whole tool or server"
        assert not any(rule == c or rule.startswith(c) for c in core), rule + " is a core tool"
    for p in g.get("pluginsOff", []):
        assert not p.startswith("coordinator@"), "the kit plugin must stay on"
PY

echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
