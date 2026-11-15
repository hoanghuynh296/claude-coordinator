#!/usr/bin/env bash
# PreToolUse guard for Edit|Write|MultiEdit|NotebookEdit.
# A session registered as coordinator may only edit coordination files; everything
# else is denied with a message telling it to delegate. Unregistered sessions: no-op.
# Limitation: only edit tools are guarded; Bash redirections (>, sed -i, tee) are not.
set -u

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(json_get "$input" session_id)" || exit 0
reg="$(registration_file "$sid")" || exit 0

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
project="$(reg_value "$reg" project)"

# 1. Ledger repo, memory/config, scratchpad and temp dirs.
for dir in "$ledger" "$HOME/.claude" "$scratch" "${TMPDIR:-}" /tmp /private/tmp /private/var/folders; do
  under "$path" "$dir" && exit 0
done

# 2. Coordinator-owned files in the project (anywhere when no project is recorded).
rel=""
if [[ -n "$project" ]]; then
  under "$path" "$project" && rel="${path#"${project%/}"/}"
else
  rel="$path"
fi
if [[ -n "$rel" ]]; then
  case "/$rel" in
    */docs/PLAN.md|*/docs/adr/*|*/docs/contracts/README.md|*/AGENTS.md)
      exit 0 ;;
  esac
fi

deny "Coordinator guard: this session is registered as the coordinator, and the coordinator never edits product code, config or shared files ($path). Delegate: put the change in a ticket (/coordinator:ticket) for the owning lane per OWNERSHIP.md, the Platform lane for root/CI files, or a one-off subagent (coordinator:oneoff-builder) that pushes its own branch and opens a PR. Allowed here: the ledger repo ($ledger), docs/PLAN.md, docs/adr/**, docs/contracts/README.md, AGENTS.md (coordinator sections), ~/.claude/**, the scratchpad and temp dirs."
