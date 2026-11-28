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
ag_p = json.load(open(os.path.join(plugin, "plugin.json")))
ag_h = json.load(open(os.path.join(plugin, "hooks.json")))
m = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
entry = m["plugins"][0]
assert entry["name"] == p["name"] == ag_p["name"], "entry name and manifest names differ"
assert p["version"] == ag_p["version"], "Claude and Antigravity plugin.json versions differ"
assert "coordinator-hooks" in ag_h, "Antigravity root hooks.json missing coordinator-hooks"
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
has references/procedures/handover.md 'next-clear.sh" <session> --handover' \
  && has references/procedures/handover.md '--add <owner/repo#N>' \
  && has references/templates/handover.md 'Pending Next' \
  && ok "handover carries pending Next PRs to the replacement" || bad "handover does not carry pending Next PRs over"
has references/procedures/review-merge.md 'whoever receives it' \
  && ok "review-merge: any message with the notice clears it, whoever receives it" || bad "review-merge does not say the notice clears whatever the recipient"
has references/procedures/review-merge.md 'autoMergeRequest' \
  && ok "review-merge checks queued auto-merges before sending Next" || bad "review-merge does not check queued --auto merges"
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

# Rotation guard (#47): wired on both runtimes for the prompt and the Stop event, and the
# coordinator's soft / hard meaning is stated where the rules live.
python3 -I - "$plugin" <<'PY4' && ok "rotation guard wired: Claude UserPromptSubmit+Stop, Antigravity PreInvocation+Stop via ag-chain" || bad "rotation guard wiring"
import json, os, sys
p = sys.argv[1]
h = json.load(open(os.path.join(p, "hooks", "hooks.json")))["hooks"]
assert any("rotation-guard.sh\" prompt" in x["command"] for e in h["UserPromptSubmit"] for x in e["hooks"])
assert any("rotation-guard.sh\" stop" in x["command"] for e in h["Stop"] for x in e["hooks"])
a = json.load(open(os.path.join(p, "hooks.json")))["coordinator-hooks"]
pre = " ".join(x["command"] for x in a["PreInvocation"]); st = " ".join(x["command"] for x in a["Stop"])
assert "ag-chain.sh prompt" in pre and "ci-watch-reminder.sh" in pre and "rotation-guard.sh:prompt" in pre
assert "ag-chain.sh stop" in st and "next-guard.sh" in st and "rotation-guard.sh:stop" in st
PY4
for f in SKILL.md references/token-economy.md references/procedures/handover.md; do
  tr '\n' ' ' <"$skill/$f" | tr -s ' ' | grep -q 'next owner desktop turn' && tr '\n' ' ' <"$skill/$f" | tr -s ' ' | grep -qi 'in this turn' \
    && ok "$f defines the coordinator's soft and hard" || bad "$f does not define coordinator soft (next owner desktop turn) / hard (in this turn)"
done
# #48: the manual "measure every context on every owner message" rule is gone. The coordinator's
# context is measured by the rotation guard, an agent's before its Next (review-merge step 9);
# no procedure, hook or script text asks for a measurement on every owner message.
hits=$(cd "$plugin" && for f in $(find skills/coordinator -name '*.md') hooks/*.sh scripts/*.sh; do
  tr '\n' ' ' <"$f" | tr -s ' ' | grep -iE 'measure[^.]*(every|each) owner message|(every|each) owner message[^.]*measure' >/dev/null && echo "$f"; done; true)
[ -z "$hits" ] && ok "no procedure, hook or script measures contexts on every owner message" || bad "manual per-message measuring rule still in: $hits"
step3=$(awk '/^## First thing in every session/{on=1} on && /^3\. /{p=1} p && /^4\. /{exit} p' "$skill/SKILL.md" | tr '\n' ' ')
case "$step3" in *"rotation guard"*"review-merge.md"*"step 9"*) ok "SKILL First thing step 3 points to the rotation guard and review-merge step 9" ;;
  *) bad "SKILL First thing step 3 does not point to the rotation guard and review-merge step 9" ;; esac
has references/procedures/handover.md 'running: <agent>, <task>' && ok "handover: running subagents go into the note" || bad "handover does not list running subagents"


# Agents report on push, the coordinator owns the CI wait (0.8.0): "PR ready" goes out once the
# PR is pushed and the local gate is green, with head SHA and CI state; agents never wait for
# CI; the coordinator starts scripts/ci-watch.sh in the background on every "PR ready".
for f in references/templates/unit-brief.md references/templates/platform-brief.md \
         references/templates/qa-brief.md ../../agents/oneoff-builder.md references/workflow.md \
         SKILL.md references/roles.md references/profile.md references/templates/PROFILE.md \
         references/procedures/review-merge.md ../../hooks/session-start.sh; do
  has "$f" 'never wait for CI\|never waiting for CI\|never waits for CI' \
    && ok "$f: agents never wait for CI" || bad "$f does not say agents never wait for CI"
  has "$f" 'head SHA\|<head sha>' && ok "$f: the report or watch names the head SHA" \
    || bad "$f does not name the head SHA"
done
for f in references/templates/unit-brief.md references/templates/PROFILE.md references/workflow.md \
         references/profile.md ../../hooks/session-start.sh SKILL.md; do
  has "$f" 'local gate' && ok "$f: reports on the local gate" || bad "$f does not speak of the local gate"
done
for f in SKILL.md references/workflow.md references/procedures/review-merge.md references/roles.md \
         references/templates/PROFILE.md references/profile.md references/pitfalls.md; do
  has "$f" 'ci-watch.sh' && ok "$f names scripts/ci-watch.sh" || bad "$f does not name ci-watch.sh"
done
has references/procedures/review-merge.md 'run_in_background' \
  && has references/procedures/review-merge.md 'new watch for the new head\|new CI watch for the new head' \
  && has references/procedures/review-merge.md 'match-head-commit' \
  && has references/procedures/review-merge.md 'only when CI is green on the reported head' \
  && ok "review-merge: background watch, a new watch after fixes, merge on green reported head" \
  || bad "review-merge lacks the background watch, re-watch after fixes or the merge condition"
for phrase in 'must be green before you report. Paste' 'Report "PR ready" when the gate is green' \
              'PR ready and gate green' 'PR ready, gate$' 'Agents own their PR until the gate is green'; do
  if grep -rq -- "$phrase" "$plugin"; then bad "the kit still says \"$phrase\""; else ok "the kit no longer says \"$phrase\""; fi
done
has references/pitfalls.md 'Both sides waited for CI' && ok "pitfalls record the CI-wait stall" \
  || bad "pitfalls miss \"Both sides waited for CI\""
ci="$plugin/scripts/ci-watch.sh"
[[ -f "$ci" ]] && ok "scripts/ci-watch.sh exists" || bad "scripts/ci-watch.sh missing"
for word in green red stale-head timeout no-checks run_in_background 'gh pr checks'; do
  grep -q -- "$word" "$ci" && ok "ci-watch.sh documents $word" || bad "ci-watch.sh does not document $word"
done
grep -q 'ci-watch-reminder.sh' "$plugin/hooks/hooks.json" && ok "hooks.json wires ci-watch-reminder.sh" \
  || bad "hooks.json does not wire ci-watch-reminder.sh"
python3 -I - "$plugin/hooks/hooks.json" <<'PY3' && ok "hooks.json: UserPromptSubmit and inbox tools run ci-watch-reminder" || bad "hooks.json ci-watch-reminder wiring"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
assert any("ci-watch-reminder.sh" in x["command"] for e in h["UserPromptSubmit"] for x in e["hooks"])
m = [e["matcher"] for e in h["PostToolUse"] if any("ci-watch-reminder.sh" in x["command"] for x in e["hooks"])]
assert m and "ReadNotifications" in m[0] and "FetchInboxMessage" in m[0]
PY3
grep -q '^- \*\*0\.11\.0\*\*' "$root/README.md" && grep -q '^- \*\*0\.11\.1\*\*' "$root/README.md" && grep -q '^- \*\*0\.12\.0\*\*' "$root/README.md" && grep -q '"version": "0.12.0"' "$plugin/.claude-plugin/plugin.json" \
  && ok "README changelog and plugin.json at 0.12.0" || bad "0.12.0 missing from README or plugin.json"
# Agents keep their Claude Code frontmatter (#40): Claude tool names, read-only Reviewer, model.
python3 -I - "$plugin" <<'PY4' && ok "agents keep Claude Code frontmatter" || bad "agent frontmatter lost its Claude Code tools or model"
import os, sys
fm = lambda n: open(os.path.join(sys.argv[1], "agents", n)).read().split("---")[1]
r, b = fm("reviewer.md"), fm("oneoff-builder.md")
assert "tools: Read, Grep, Glob, Bash" in r and "disallowedTools: Edit, Write" in r and "model: opus" in r
assert "\ntools:" not in b and "model: sonnet" in b
PY4
# Same-session next issue (0.9.0): the strict conditions are stated where the coordinator and the agent read them.
for f in SKILL.md references/workflow.md references/profile.md references/pitfalls.md references/procedures/review-merge.md references/templates/PROFILE.md references/templates/unit-brief.md; do
  has "$f" '(same session)' && ok "$f gives the same-session Next" || bad "$f lacks the same-session Next"
done
for f in references/procedures/review-merge.md SKILL.md references/profile.md; do
  has "$f" '175k' && has "$f" 'cannot start a session' && has "$f" 'fewer than 3' && ok "$f states the 175k, no-start and fewer-than-3 conditions" || bad "$f lacks the 175k / no-start / 3-issue conditions"
done
# C-016 (#23): the same-session cap is a Budgets line, default 175k; no "50% of soft" rule is left.
has references/profile.md 'Same-session cap: 175k' && has references/templates/PROFILE.md 'Same-session cap' \
  && ok "same-session cap in profile Budgets" || bad "same-session cap missing from profile Budgets"
for f in SKILL.md references/workflow.md references/profile.md references/pitfalls.md references/procedures/review-merge.md references/templates/PROFILE.md; do
  ! grep -q '50% of \(the unit.s \)\?soft' "$f" && ok "$f has no 50%-of-soft rule" || bad "$f still has the 50%-of-soft rule"
done
# C-015 / C-017 defaults (#24): coordinator 300k/450k, Reviewer size trigger, one ledger commit per turn.
for f in SKILL.md references/profile.md references/templates/PROFILE.md; do
  has "$f" '300k' && has "$f" '450k' && has "$f" '--role coordinator' && ok "$f gives the coordinator 300k / 450k" || bad "$f lacks the coordinator 300k / 450k"
done
! grep -rq 'soft 400k, hard 700k' "$skill" && ok "no 400k / 700k coordinator default left" || bad "an old 700k coordinator default is left"
for f in references/procedures/review-merge.md references/profile.md references/templates/PROFILE.md; do
  has "$f" '400 changed lines' && has "$f" '25 hand-written files' && has "$f" '\*\*/vendor/\*\*' && has "$f" 'release PR is exempt' \
    && ok "$f states the Reviewer size trigger" || bad "$f lacks the Reviewer size trigger"
done
for f in references/state-files.md references/procedures/review-merge.md; do
  has "$f" 'one ledger commit\|one commit' && ok "$f batches ledger commits per turn" || bad "$f lacks one ledger commit per turn"
done
# Archive fallback: two calls, then rename "(old)" and one batched owner line.
for f in SKILL.md references/procedures/review-merge.md references/workflow.md references/procedures/handover.md; do
  has "$f" '(old)' && has "$f" 'Archive finished sessions: <names>' \
    && ok "$f gives the archive fallback (rename (old), one owner line)" \
    || bad "$f does not give the archive fallback (rename \"(old)\", one line \"Archive finished sessions: <names>\")"
done
has references/procedures/audit.md 'Archive finished sessions' && has references/procedures/audit.md '(old)' \
  && ok "audit checks the archive line and (old) sessions" || bad "audit does not check the archive line and (old) sessions"
has references/pitfalls.md 'Archive finished sessions: <names>' && ok "pitfalls records the archive fallback" \
  || bad "pitfalls lacks the archive fallback entry"

# Template gaps: Deploy, files with no unit, release notes, pending starts, briefs, review rules.
has references/templates/PROFILE.md '## 9. Deploy' && has references/templates/PROFILE.md 'Deploy-only' \
  && has references/templates/PROFILE.md 'Files with no unit' && ok "PROFILE template has Deploy and Files with no unit" \
  || bad "PROFILE template lacks Deploy / Files with no unit"
has references/templates/ROADMAP.md 'Release notes draft' && ok "ROADMAP template has Release notes draft" || bad "ROADMAP template lacks Release notes draft"
has references/templates/COORDINATION.md 'Pending starts' && ok "COORDINATION template has Pending starts" || bad "COORDINATION template lacks Pending starts"
[[ -f "$skill/references/templates/ops-brief.md" ]] && has references/templates/ops-brief.md 'No PR' \
  && ok "ops-brief template exists" || bad "ops-brief template missing"
has references/templates/unit-brief.md 'Cross-lane mini-exception' && ok "unit-brief has the cross-lane mini-exception" || bad "unit-brief lacks the cross-lane mini-exception"
for f in references/procedures/review-merge.md references/workflow.md; do
  has "$f" 'fix commits' && has "$f" 'contract or migration PR first\|contract or' && ok "$f: Reviewer re-run on fix commits and the risk split" \
    || bad "$f lacks the fix-commit re-review / risk split rule"
done
has references/workflow.md 'waits on <project>#N' && has references/workflow.md 'self-report' \
  && ok "workflow: cross-project items and measured context" || bad "workflow lacks cross-project / measured-context rules"
for f in references/procedures/milestone-close.md references/workflow.md references/templates/PROFILE.md references/procedures/kickoff.md references/pitfalls.md; do
  has "$f" 'release/vX.Y.Z' && has "$f" 'back-merge' && ok "$f: release standard (release/vX.Y.Z, back-merge)" || bad "$f lacks the release standard"
done
has references/templates/PROFILE.md 'Tag-only repo' && ok "PROFILE template: tag-only note" || bad "PROFILE template lacks the tag-only note"
has references/procedures/review-merge.md 'gh issue close' && ok "review-merge: coordinator closes the linked issue" || bad "review-merge lacks gh issue close"
# One call per ledger commit (#50): the skill, state files and procedures that commit the
# ledger name ledger-commit.sh; none still asks for a separate lint before the commit.
for f in SKILL.md references/state-files.md references/pitfalls.md references/workflow.md \
         references/procedures/audit.md references/procedures/handover.md references/procedures/kickoff.md \
         references/procedures/milestone-start.md references/procedures/review-merge.md \
         references/procedures/status.md references/procedures/ticket.md references/procedures/token-audit.md; do
  has "$f" 'ledger-commit.sh' && ok "$f names ledger-commit.sh" || bad "$f does not name ledger-commit.sh"
done
if grep -rqi -- 'lint, commit and push\|before every ledger commit\|before every commit' "$plugin/skills"; then
  bad "the kit still asks for a separate lint before the ledger commit"
else ok "no separate lint-before-commit step left"; fi
has references/procedures/audit.md 'install-guards.sh' && ok "audit installs the missing pre-commit hook" \
  || bad "audit does not install the pre-commit hook"
[[ -x "$plugin/scripts/ledger-commit.sh" ]] && ok "scripts/ledger-commit.sh exists" || bad "scripts/ledger-commit.sh missing"
# Merge in one call (#49): review-merge uses merge-pr.sh and keeps the manual fallback; the
# script keeps the merge contract.
has references/procedures/review-merge.md 'merge-pr.sh' && has references/procedures/review-merge.md 'Fallback when the script cannot run' \
  && ok "review-merge uses merge-pr.sh with the manual fallback" || bad "review-merge lacks merge-pr.sh or the fallback"
mp="$plugin/scripts/merge-pr.sh"
[[ -x "$mp" ]] && ok "scripts/merge-pr.sh exists" || bad "scripts/merge-pr.sh missing"
for word in '--delete-branch' '--match-head-commit' 'merged. Next:' 'pending_add' 'next_exempt'; do
  grep -q -- "$word" "$mp" && ok "merge-pr.sh has $word" || bad "merge-pr.sh lacks $word"
done
echo "passed $pass, failed $failn"
[[ $failn -eq 0 ]]
