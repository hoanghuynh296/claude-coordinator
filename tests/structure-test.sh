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
# the coordinator by name, the app setting auto_archive_on_pr_close is checked at registration,
# and the coordinator archives a per-issue agent's session after merging its PR.
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
for f in SKILL.md references/procedures/coordinator-register.md references/procedures/kickoff.md \
         references/procedures/adopt.md references/procedures/audit.md references/templates/PROFILE.md; do
  has "$f" 'auto_archive_on_pr_close' && ok "$f names the setting auto_archive_on_pr_close" \
    || bad "$f does not name auto_archive_on_pr_close"
done
has references/procedures/coordinator-register.md 'get_settings' \
  && has references/procedures/coordinator-register.md 'set_setting' \
  && ok "coordinator-register reads the setting and asks the owner to turn it off" \
  || bad "coordinator-register does not read (get_settings) and change (set_setting) the setting"
for f in SKILL.md references/workflow.md references/procedures/review-merge.md; do
  has "$f" 'archive_session' && ok "$f archives a per-issue agent's session after its merge" \
    || bad "$f does not name archive_session"
  has "$f" 'archived only' && ok "$f archives a standing session only on rotation" \
    || bad "$f does not say a standing session is archived only on rotation"
done
for f in references/profile.md references/roles.md SKILL.md; do
  has "$f" 'archive.\{0,30\}per-issue\|per-issue.\{0,60\}archived by the coordinator' \
    && ok "$f: the coordinator archives per-issue sessions" || bad "$f does not say the coordinator archives per-issue sessions"
done
for f in references/procedures/handover.md references/templates/handover.md SKILL.md; do
  has "$f" 'coordinator archives a `per-issue` session right after its PR merges' \
    && ok "$f: handover before the last merge, since the coordinator archives right after" \
    || bad "$f does not tie the handover timing to the coordinator's archive"
done
# unbind_pr survives only as the fallback for a setting still on
for f in SKILL.md references/workflow.md references/procedures/review-merge.md \
         references/procedures/coordinator-register.md; do
  if tr '\n' ' ' <"$skill/$f" | tr -s ' ' | grep -o '.\{0,250\}unbind_pr' | grep -qv 'still on\|stays on\|setting is still'; then
    bad "$f names unbind_pr outside the setting-still-on fallback"
  else ok "$f: unbind_pr only as a fallback"; fi
done
grep -q 'merge-reminder.sh' "$plugin/hooks/hooks.json" && ok "hooks.json wires the merge reminder" \
  || bad "hooks.json does not wire merge-reminder.sh" 
for f in SKILL.md references/workflow.md references/procedures/handover.md; do
  has "$f" 'never started by the session it replaces' && ok "$f: a replacement is not started by the session it replaces" \
    || bad "$f lacks the replacement-starter rule"
  has "$f" '(old)' && ok "$f: the old session gives up its name before the replacement takes it" \
    || bad "$f does not rename the old session \"<name> (old)\""
done
has references/procedures/coordinator-register.md 'set_session_title' \
  && has references/procedures/coordinator-register.md 'only live session with that name' \
  && ok "coordinator-register names the session and checks the name is unique" \
  || bad "coordinator-register does not set and check the name \"Coordinator: <project>\""
for f in kickoff adopt; do
  grep -q 'coordinator-register' "$skill/references/procedures/$f.md" && ok "$f reaches the naming step through coordinator-register" \
    || bad "$f does not follow coordinator-register"
done
has references/templates/unit-brief.md 'final answer is the report' && ok "unit-brief gives the subagent fallback's report" \
  || bad "unit-brief lacks the subagent exception"
has references/templates/unit-brief.md 'handover written' && ok "unit-brief reports \"handover written\"" \
  || bad "unit-brief does not report \"handover written\""
has references/pitfalls.md 'Nested chains on rotation' && has references/pitfalls.md 'archived with its PR' \
  && has references/pitfalls.md 'auto_archive_on_pr_close' && has references/pitfalls.md 'any `gh` touch\|touches with `gh`' \
  && ok "pitfalls record nested chains and PR auto-archive" || bad "pitfalls miss nested chains or PR auto-archive"


# One issue, one full lifecycle (0.7.0): agents take one issue, report "PR ready" with their
# context and wait for "PR #N merged. Next: ..."; the coordinator sends that in the merge turn,
# and hooks enforce it.
for f in references/templates/unit-brief.md references/templates/platform-brief.md \
         references/templates/qa-brief.md ../../agents/oneoff-builder.md references/workflow.md \
         SKILL.md references/roles.md references/profile.md references/templates/PROFILE.md \
         references/procedures/review-merge.md references/pitfalls.md; do
  has "$f" 'PR #<n> merged. Next:' && ok "$f gives the merge notice \"PR #<n> merged. Next: ...\"" \
    || bad "$f does not give the merge notice format"
done
for f in references/templates/unit-brief.md ../../agents/oneoff-builder.md references/workflow.md \
         SKILL.md references/profile.md references/templates/PROFILE.md; do
  has "$f" 'Context: <k tokens>' && ok "$f: reports end with Context: <k tokens>" \
    || bad "$f does not end reports with \"Context: <k tokens>\""
done
for f in references/templates/unit-brief.md references/workflow.md SKILL.md references/roles.md \
         references/profile.md references/templates/PROFILE.md ../../agents/oneoff-builder.md; do
  has "$f" 'one issue at a time\|One issue at a time\|ONE issue\|one full lifecycle\|One task, one full lifecycle' \
    && ok "$f: one issue at a time" || bad "$f does not say one issue at a time"
done
has SKILL.md 'either working on the issue it was given or waiting on the coordinator' \
  && ok "SKILL.md: an agent is working or waiting on the coordinator" || bad "SKILL.md lacks working-or-waiting"
has references/procedures/review-merge.md 'same turn as the merge' \
  && has references/procedures/review-merge.md 'get_usage' \
  && has references/procedures/review-merge.md 'next-clear.sh' \
  && ok "review-merge step 9: context, Next message in the merge turn, escape hatch" \
  || bad "review-merge step 9 lacks the same-turn Next message, get_usage or next-clear.sh"
has references/procedures/review-merge.md 'reports "PR ready" again and waits again' \
  && ok "review-merge: after findings the agent fixes, reports and waits" || bad "review-merge: findings loop not stated"
has references/pitfalls.md 'Both sides waited after a merge' && ok "pitfalls record the post-merge stall" \
  || bad "pitfalls miss the post-merge stall"
for phrase in 'continue without asking' 'Tell the agent nothing about the merge' 'Silence means' \
              'next two or three' 'next one or two in order'; do
  if grep -rqi -- "$phrase" "$plugin"; then bad "the kit still says \"$phrase\""; else ok "the kit no longer says \"$phrase\""; fi
done
for h in next-sent.sh next-guard.sh; do
  grep -q "$h" "$plugin/hooks/hooks.json" && ok "hooks.json wires $h" || bad "hooks.json does not wire $h"
done
python3 -I - "$plugin/hooks/hooks.json" <<'PY2' && ok "hooks.json: Stop runs next-guard, SendMessage tools run next-sent" || bad "hooks.json event wiring"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
assert any("next-guard.sh" in x["command"] for e in h["Stop"] for x in e["hooks"])
m = [e["matcher"] for e in h["PostToolUse"] if any("next-sent.sh" in x["command"] for x in e["hooks"])]
assert m and "SendMessage" in m[0] and "mcp__ccd_session_mgmt__send_message" in m[0]
PY2

echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
