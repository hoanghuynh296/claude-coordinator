#!/usr/bin/env bash
# PreToolUse guard for Edit|Write|MultiEdit|NotebookEdit.
# A session registered as coordinator may only edit coordination files; everything else is
# denied with a message telling it to delegate. Unregistered sessions, and sessions registered
# with guard=off, are never affected.
#
# Order of the checks matters for multi-repo workspaces, where unit checkouts sit INSIDE the
# ledger repo (products/<unit>): a path under a unit is judged by the unit rules first, and
# only paths outside every unit may be allowed because they are in the ledger.
# Limitation: only edit tools are guarded; Bash redirections (>, sed -i, tee) are not.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
reg="$(registration_file "$sid")" || exit 0
[[ "$(reg_value "$reg" guard)" == "off" ]] && exit 0

path="$(json_get "$input" tool_input.file_path)"
[[ -z "$path" ]] && path="$(json_get "$input" tool_input.notebook_path)"
[[ -z "$path" ]] && exit 0

cwd="$(json_get "$input" cwd)"
scratch="$(json_get "$input" scratchpad_dir)"
[[ "$path" != /* ]] && path="${cwd:-$PWD}/$path"

deny() {
  local reason="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(json_string "$reason")"
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

allow_text="nothing"
[[ ${#allows[@]} -gt 0 ]] && { allow_text="$(printf '%s, ' "${allows[@]}")"; allow_text="${allow_text%, }"; }
delegate="Delegate: write an issue for the owning unit (/coordinator:ticket), or use a one-off subagent (coordinator:oneoff-builder) that pushes its own branch and opens a PR."

# 1. Inside a unit: only the allowed planning files.
if [[ ${#units[@]} -gt 0 ]]; then
  for unit in "${units[@]}"; do
    if under "$path" "$unit"; then
      rel="${path#"${unit%/}"/}"
      allowed_rel "$rel" && exit 0
      deny "Coordinator guard: this session is registered as the coordinator and may not edit $path (inside unit $unit). $delegate Allowed inside units: $allow_text. Allowed elsewhere: the ledger repo ($ledger), ~/.claude/**, the scratchpad and temp dirs."
    fi
  done
fi

# 2. Ledger repo, memory/config, scratchpad and temp dirs.
for dir in "$ledger" "$HOME/.claude" "$scratch" "${TMPDIR:-}" /tmp /private/tmp /private/var/folders; do
  under "$path" "$dir" && exit 0
done

# 3. No unit recorded: the allowed planning files anywhere.
if [[ ${#units[@]} -eq 0 ]] && allowed_rel "${path#/}"; then
  exit 0
fi

deny "Coordinator guard: this session is registered as the coordinator and may not edit $path. $delegate Allowed: the ledger repo ($ledger), inside units only $allow_text, ~/.claude/**, the scratchpad and temp dirs."
