#!/usr/bin/env bash
# The plugin's parts agree with each other: every command is a thin wrapper around a procedure
# of the skill, the skill routes plain language to every procedure, the skill listing text
# fits the size cap, and every file the skill names exists.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
plugin="$root/plugins/coordinator"
skill="$plugin/skills/coordinator"
pass=0; failn=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
bad() { failn=$((failn+1)); echo "FAIL $1"; }

for cmd in "$plugin"/commands/*.md; do
  name="$(basename "$cmd" .md)"
  [[ -f "$skill/references/procedures/$name.md" ]] && ok "procedure exists for /coordinator:$name" || bad "no procedure for command $name"
  grep -q "references/procedures/$name.md" "$cmd" && ok "command $name points at its procedure" || bad "command $name does not point at its procedure"
  grep -q "references/procedures/$name.md\|\`$name.md\`" "$skill/SKILL.md" && ok "skill routes to $name" || bad "skill does not mention procedure $name"
done
for proc in "$skill"/references/procedures/*.md; do
  name="$(basename "$proc" .md)"
  [[ -f "$plugin/commands/$name.md" ]] && ok "command exists for procedure $name" || bad "no command for procedure $name"
  if grep -q 'CLAUDE_PLUGIN_ROOT\|CLAUDE_SESSION_ID\|\$ARGUMENTS' "$proc"; then
    bad "procedure $name uses a substitution variable (only SKILL.md and commands are substituted)"
  else ok "procedure $name has no substitution variable"; fi
done

python3 -I - "$skill" <<'PY' && ok "skill listing text fits the cap and named files exist" || bad "skill frontmatter or named files"
import os, re, sys
skill = sys.argv[1]
text = open(os.path.join(skill, "SKILL.md"), encoding="utf-8").read()
m = re.match(r"---\n(.*?)\n---\n", text, re.S)
assert m, "no frontmatter"
front = m.group(1)
desc = re.search(r"^description: (.*)$", front, re.M)
when = re.search(r"^when_to_use: (.*)$", front, re.M)
assert desc, "no description"
total = len(desc.group(1)) + (len(when.group(1)) if when else 0)
assert total <= 1536, f"description + when_to_use is {total} characters, cap 1536"
for var in ("${CLAUDE_PLUGIN_ROOT}", "${CLAUDE_SESSION_ID}", "${CLAUDE_SKILL_DIR}"):
    assert var in text, f"SKILL.md must give {var} under Paths"
missing = []
for rel in sorted(set(re.findall(r"`(references/[A-Za-z0-9_./-]+\.md)`", text))):
    if not os.path.isfile(os.path.join(skill, rel)):
        missing.append(rel)
for group, names in re.findall(r"`(references/(?:packs|templates)/)`: ((?:`[A-Za-z0-9_.-]+\.md`[,. \n]*)+)", text):
    for n in re.findall(r"`([A-Za-z0-9_.-]+\.md)`", names):
        if not os.path.isfile(os.path.join(skill, group, n)):
            missing.append(group + n)
assert not missing, f"named but missing: {missing}"
PY

python3 -I - "$plugin" "$root" <<'PY' && ok "plugin.json and marketplace.json agree" || bad "manifest mismatch"
import json, os, sys
plugin, root = sys.argv[1:3]
p = json.load(open(os.path.join(plugin, ".claude-plugin", "plugin.json")))
m = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
entry = m["plugins"][0]
assert entry["name"] == p["name"], "entry name and manifest name differ"
assert os.path.isdir(os.path.join(root, entry["source"])), "plugin source path missing"
assert p["version"].count(".") == 2, "version is not x.y.z"
PY

echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
