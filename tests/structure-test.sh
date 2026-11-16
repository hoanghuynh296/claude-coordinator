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

# The context thresholds have one set of defaults (soft 250k, hard 400k) wherever they are
# stated (each file that states them names both), and the per-issue handover rule reads the same in every place that gives it.
for f in scripts/check-context.sh skills/coordinator/SKILL.md skills/coordinator/references/profile.md \
         skills/coordinator/references/workflow.md skills/coordinator/references/templates/PROFILE.md \
         skills/coordinator/references/templates/unit-brief.md agents/oneoff-builder.md; do
  if grep -q '250k' "$plugin/$f" && grep -q '400k' "$plugin/$f"; then ok "$f states the 250k/400k defaults"
  else bad "$f does not state both defaults 250k and 400k"; fi
done
for f in SKILL.md references/workflow.md references/procedures/handover.md references/templates/unit-brief.md; do
  tr '\n' ' ' <"$skill/$f" | tr -s ' ' | grep -q 'no handover file' && ok "$f gives the per-issue handover rule" \
    || bad "$f does not give the per-issue handover rule (no handover file; at hard, into the PR)"
done

# Sessions are top-level peers: starters detach what they start, agents report by message to
# the coordinator by name, and the coordinator unbinds a PR after merging it.
has() { tr '\n' ' ' <"$skill/$1" | tr -s ' ' | grep -q -- "$2"; }
for f in SKILL.md references/workflow.md references/procedures/milestone-start.md \
         references/procedures/handover.md references/procedures/coordinator-register.md \
         references/templates/unit-brief.md; do
  has "$f" 'detach_session' && ok "$f says to detach sessions to the top level" \
    || bad "$f does not name detach_session"
done
for f in SKILL.md references/workflow.md references/roles.md references/templates/PROFILE.md \
         references/templates/unit-brief.md references/templates/platform-brief.md \
         references/templates/qa-brief.md ../../agents/oneoff-builder.md; do
  has "$f" 'Coordinator: <project>\|Coordinator: {{PROJECT_NAME}}' && ok "$f names the coordinator session reports go to" \
    || bad "$f does not name \"Coordinator: <project>\" as where reports go"
done
for f in SKILL.md references/workflow.md references/procedures/review-merge.md \
         references/procedures/coordinator-register.md; do
  has "$f" 'unbind_pr' && ok "$f says to unbind a merged PR" || bad "$f does not name unbind_pr"
done
has SKILL.md 'never started by the session it replaces' && ok "SKILL.md: a replacement is not started by the session it replaces" \
  || bad "SKILL.md lacks the replacement-starter rule"
has references/templates/unit-brief.md 'handover written' && ok "unit-brief reports \"handover written\"" \
  || bad "unit-brief does not report \"handover written\""
has references/pitfalls.md 'Nested chains on rotation' && has references/pitfalls.md 'archived with its PR' \
  && ok "pitfalls record nested chains and PR auto-archive" || bad "pitfalls miss nested chains or PR auto-archive"

echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
