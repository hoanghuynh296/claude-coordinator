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

echo "--- the lock records what the kit added"
lock="$w/repo/.claude/lean-tools.lock.json"
lockhas() {
  if python3 -I -c 'import json,sys; l=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' \
      "$lock" "$2" 2>/dev/null; then ok "$1"; else bad "$1"; fi
}
lockhas "lock lists the deny rule it added"   "'mcp__computer-use' in l['deny']"
lockhas "lock lists the skill it turned off"  "'cloudflare:wrangler' in l['skillOverrides']"
lockhas "lock lists the setting it set"       "l['settings'] == ['disableClaudeAiConnectors']"

echo "--- existing settings are merged, never overwritten"
rm -f "$lock"
cat > "$cfg" <<'JSON'
{
  "title": "Dự án mẫu",
  "model": "opus",
  "hooks": {"Stop": []},
  "permissions": {"allow": ["Bash(npm test)"], "deny": ["Bash(rm -rf *)", "mcp__Claude_Browser"]},
  "skillOverrides": {"my-skill": "name-only", "cloudflare:wrangler": "name-only", "anthropic-skills:docx": "off"},
  "enabledPlugins": {"foo@bar": true},
  "disableClaudeAiConnectors": true
}
JSON
out="$(guards --tools "semi-design")"
[[ "$out" == *"warning: skillOverrides 'cloudflare:wrangler' is 'name-only'"* ]] && ok "different value warns" || bad "no warning: $out"
check "key order kept, title first"   "list(s)[0] == 'title'"
check "unrelated keys kept"           "s['model'] == 'opus' and s['hooks'] == {'Stop': []}"
check "allow rules kept"              "s['permissions']['allow'] == ['Bash(npm test)']"
check "own deny rule kept first"      "s['permissions']['deny'][0] == 'Bash(rm -rf *)'"
check "no duplicate deny rules"       "len(s['permissions']['deny']) == len(set(s['permissions']['deny']))"
check "own skill override kept"       "s['skillOverrides']['my-skill'] == 'name-only'"
check "user's name-only not overwritten" "s['skillOverrides']['cloudflare:wrangler'] == 'name-only'"
check "own plugin kept"               "s['enabledPlugins'] == {'foo@bar': True}"
grep -q 'Dự án mẫu' "$cfg" && ok "UTF-8 written as is" || bad "non-ASCII escaped"
[[ "$(tail -c 1 "$cfg" | od -An -c | tr -d ' ')" == '\n' ]] && ok "trailing newline" || bad "no trailing newline"
lockhas "user's identical entries not in lock" "'mcp__Claude_Browser' not in l['deny'] and 'anthropic-skills:docx' not in l['skillOverrides'] and 'settings' not in l"
lockhas "user's different value not in lock"   "'cloudflare:wrangler' not in l['skillOverrides']"
cp "$cfg" "$w/merged.json"; cp "$lock" "$w/merged.lock"
guards --tools "semi-design" >/dev/null
cmp -s "$cfg" "$w/merged.json" && cmp -s "$lock" "$w/merged.lock" && ok "merged files stable on re-run" || bad "merged files changed on re-run"

echo "--- keeping a group removes only what the kit added"
guards --tools "semi-design cloudflare browser connectors office" >/dev/null
check "kit's cloudflare deny removed" "'mcp__plugin_cloudflare_cloudflare' not in s['permissions']['deny']"
check "user's browser deny survives"  "'mcp__Claude_Browser' in s['permissions']['deny']"
check "user's docx off survives"      "s['skillOverrides']['anthropic-skills:docx'] == 'off'"
check "user's connectors setting survives" "s['disableClaudeAiConnectors'] is True"
check "user's name-only survives"     "s['skillOverrides']['cloudflare:wrangler'] == 'name-only'"
check "kit's skill of a kept group removed" "'cloudflare:k2' not in s['skillOverrides']"
check "own rule still there"          "'Bash(rm -rf *)' in s['permissions']['deny']"
lockhas "lock drops what was removed"  "'mcp__plugin_cloudflare_cloudflare' not in l['deny']"
guards --tools none >/dev/null
check "none: semi-design plugin off"  "s['enabledPlugins']['semi-design@semi-marketplace'] is False and s['enabledPlugins']['foo@bar'] is True"
guards --tools "browser semi-design cloudflare chrome computer-use office docs artifacts desktop-extras connectors ios-simulator" >/dev/null
check "all kept: user's entries left" "s['permissions']['deny'] == ['Bash(rm -rf *)', 'mcp__Claude_Browser'] and s['enabledPlugins'] == {'foo@bar': True}"
[[ ! -e "$lock" ]] && ok "all kept: lock removed" || bad "lock left with nothing in it"

echo "--- symlinked settings write the target"
mv "$cfg" "$w/shared.json"; ln -s "$w/shared.json" "$cfg"
guards --tools none >/dev/null
[[ -L "$cfg" ]] && ok "symlink kept" || bad "symlink replaced by a file"
grep -q 'mcp__computer-use' "$w/shared.json" && ok "target written" || bad "target not written"
ls "$w/repo/.claude"/.lean-tools.* >/dev/null 2>&1 && bad "temp file left" || ok "no temp file left"
rm -f "$cfg"; cp "$w/shared.json" "$cfg"

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
