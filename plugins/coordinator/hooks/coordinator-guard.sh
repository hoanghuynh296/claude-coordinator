#!/usr/bin/env bash
# PreToolUse guard for Edit|Write|MultiEdit|NotebookEdit.
# A session registered as coordinator may only edit coordination files; everything else is
# denied with a message telling it to delegate. Unregistered sessions, and sessions registered
# with guard=off, are never affected. Subagents share the coordinator's session id and so its
# guard; only a coordinator:oneoff-builder writing inside its own worktree is let through
# (builder_ok below, Claude Code only).
#
# Order of the checks matters for multi-repo workspaces, where unit checkouts sit INSIDE the
# ledger repo (products/<unit>): a path under a unit is judged by the unit rules first, and
# only paths outside every unit may be allowed because they are in the ledger.
# Limitation: only edit tools are guarded; Bash redirections (>, sed -i, tee) are not.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(hook_sid "$input")" || exit 0
ag=0; is_antigravity "$input" && ag=1
allow() {
  (( ag )) && printf '{"decision":"allow"}\n'
  exit 0
}
reg="$(registration_file "$sid")" || allow
[[ "$(reg_value "$reg" guard)" == "off" ]] && allow

path="$(json_get "$input" tool_input.file_path)"
[[ -z "$path" ]] && path="$(json_get "$input" tool_input.notebook_path)"
[[ -z "$path" ]] && path="$(json_get "$input" toolCall.args.Path)"
[[ -z "$path" ]] && path="$(json_get "$input" toolCall.args.TargetFile)"
[[ -z "$path" ]] && allow

cwd="$(json_get "$input" cwd)"
scratch="$(json_get "$input" scratchpad_dir)"
[[ -z "$scratch" ]] && scratch="$(json_get "$input" artifactDirectoryPath)"
[[ "$path" != /* ]] && path="${cwd:-$PWD}/$path"

deny() {
  local reason="$1"
  if (( ag )); then
    printf '{"decision":"deny","reason":%s}\n' "$(json_string "$reason")"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
      "$(json_string "$reason")"
  fi
  exit 0
}

# Normalize ".." and "." segments; refuse to guess when no python3 is available.
case "$path" in
  */../*|*/..|*/./*|*/.|*//*)
    if command -v python3 >/dev/null 2>&1; then
      path="$(python3 -I -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$path")"
    else
      deny "Coordinator guard: cannot normalize path '$path'. Use an absolute path without '..'."
    fi
    ;;
esac

under() { [[ -n "$2" && ( "$1" == "$2" || "$1" == "${2%/}/"* ) ]]; }

# 0. The builder claims (hook state) are never written with an edit tool, by anyone. Compared on
# real paths and case-insensitively, so a symlink or another letter case does not get around it.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
rpath="$path"; rhome="$COORD_HOME"
if command -v python3 >/dev/null 2>&1; then
  rpath="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path")"
  rhome="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$COORD_HOME")"
fi
for p in "$path" "$rpath"; do
  for h in "$COORD_HOME" "$rhome"; do
    case "$(lc "$p")" in
      "$(lc "${h%/}")"/state/*/builders|"$(lc "${h%/}")"/state/*/builders/*)
        deny "Coordinator guard: $path holds the builder worktree claims; no edit tool may write it." ;;
    esac
  done
done

ledger="$(reg_value "$reg" ledger)"

units=()
while IFS= read -r u; do [[ -n "$u" ]] && units+=("$u"); done < <(reg_values "$reg" unit; reg_values "$reg" project)
allows=()
while IFS= read -r a; do [[ -n "$a" ]] && allows+=("$a"); done < <(reg_values "$reg" allow)
if [[ "$(reg_value "$reg" allow_none)" == "1" ]]; then
  allows=()
elif [[ ${#allows[@]} -eq 0 ]]; then
  allows=("docs/PLAN.md" "docs/adr/*" "docs/contracts/README.md" "AGENTS.md")
fi

# allowed_rel <path relative to a unit root>: matches an allow glob at the unit root or deeper
# (so "AGENTS.md" also allows web/AGENTS.md, as the first version of this guard did).
allowed_rel() {
  local rel="$1" g
  for g in ${allows[@]+"${allows[@]}"}; do
    # shellcheck disable=SC2254  # the allow entries are globs on purpose
    case "$rel" in
      $g|*/$g) return 0 ;;
    esac
  done
  return 1
}

# builder_ok: 0 when this call comes from a coordinator:oneoff-builder subagent and $path lies
# inside that subagent's own worktree <unit>/.claude/worktrees/builder-<name>/. Claude Code
# only: its PreToolUse input carries agent_id (present only inside a subagent) and agent_type.
# Antigravity's payload names no subagent, so there a builder is judged as the coordinator.
# The worktree must be a linked git worktree (.git is a file), reached without symlinks, and
# is claimed by the first builder that writes in it: one worktree per builder, one builder per
# worktree. Anything it cannot establish returns 1, and the coordinator rules below apply.
aid="$(json_get "$input" agent_id)"
# claim <file> <value>: create <file> holding <value> unless it exists (noclobber is atomic);
# 0 when the file now holds <value>.
claim() {
  ( set -C; printf '%s\n' "$2" >"$1" ) 2>/dev/null || true
  [[ "$(head -n 1 "$1" 2>/dev/null)" == "$2" ]]
}
# worktree_key <unit> <name> <path>: prints "<dev>-<inode>" of <unit>/.claude/worktrees/<name>
# when <name> is that directory's entry on disk (exact case, for case-insensitive APFS), none of
# .claude, worktrees, the worktree and its .git is a symlink, .git is a file (linked worktree),
# and the real paths of the worktree and of <path> stay inside the real unit and the worktree.
worktree_key() {
  python3 -I -c '
import os, sys
unit, name, path = sys.argv[1:4]
dot = os.path.join(unit, ".claude"); root = os.path.join(dot, "worktrees"); wt = os.path.join(root, name)
if any(os.path.islink(p) for p in (dot, root, wt, os.path.join(wt, ".git"))): sys.exit(1)
if name not in os.listdir(root) or not os.path.isfile(os.path.join(wt, ".git")): sys.exit(1)
ru, rwt, rp = (os.path.realpath(p) for p in (unit, wt, path))
if not (rwt.startswith(ru + os.sep) and rp.startswith(rwt + os.sep)): sys.exit(1)
st = os.stat(wt)
print("%d-%d" % (st.st_dev, st.st_ino))
' "$1" "$2" "$3" 2>/dev/null
}
builder_ok() {
  (( ag )) && return 1
  local atype unit uroot rest name key d
  atype="$(json_get "$input" agent_type)"
  [[ "$aid" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  case "$atype" in coordinator:oneoff-builder|oneoff-builder) ;; *) return 1 ;; esac
  command -v python3 >/dev/null 2>&1 || return 1
  for unit in ${units[@]+"${units[@]}"}; do
    uroot="${unit%/}/.claude/worktrees"
    [[ "$path" == "$uroot/"* ]] || continue
    rest="${path#"$uroot"/}"; name="${rest%%/*}"
    [[ "$rest" == */* && "$rest" != "$name/.git" && "$name" =~ ^builder-[A-Za-z0-9._-]+$ ]] || return 1
    key="$(worktree_key "${unit%/}" "$name" "$path")" && [[ "$key" =~ ^[0-9]+-[0-9]+$ ]] || return 1
    d="$(state_dir "$sid")" || return 1; d="$d/builders"; mkdir -p "$d" || return 1
    claim "$d/agent-$aid" "$key" && claim "$d/wt-$key" "$aid"
    return
  done
  return 1
}
builder_ok && allow

allow_text="nothing"
[[ ${#allows[@]} -gt 0 ]] && { allow_text="$(printf '%s, ' "${allows[@]}")"; allow_text="${allow_text%, }"; }
delegate="Delegate: write an issue for the owning unit (the coordinator skill's ticket procedure), or use a one-off subagent (coordinator:oneoff-builder) that pushes its own branch and opens a PR."
[[ -n "$aid" ]] && delegate="This call came from a subagent of the coordinator: only a coordinator:oneoff-builder may write, and only inside its own worktree <unit>/.claude/worktrees/builder-<name>/ (one worktree per builder, created with git worktree add)."

# 1. Inside a unit: only the allowed planning files.
if [[ ${#units[@]} -gt 0 ]]; then
  for unit in "${units[@]}"; do
    if under "$path" "$unit"; then
      rel="${path#"${unit%/}"/}"
      allowed_rel "$rel" && allow
      deny "Coordinator guard: this session is registered as the coordinator and may not edit $path (inside unit $unit). $delegate Allowed inside units: $allow_text. Allowed elsewhere: the ledger repo ($ledger), ~/.claude/**, ~/.gemini/**, the scratchpad and temp dirs."
    fi
  done
fi

# 2. Ledger repo, memory/config, scratchpad and temp dirs.
for dir in "$ledger" "$HOME/.claude" "$HOME/.gemini" "$scratch" "${TMPDIR:-}" /tmp /private/tmp /private/var/folders; do
  under "$path" "$dir" && allow
done

# 3. No unit recorded: the allowed planning files anywhere.
if [[ ${#units[@]} -eq 0 ]] && allowed_rel "${path#/}"; then
  allow
fi

deny "Coordinator guard: this session is registered as the coordinator and may not edit $path. $delegate Allowed: the ledger repo ($ledger), inside units only $allow_text, ~/.claude/**, ~/.gemini/**, the scratchpad and temp dirs."
