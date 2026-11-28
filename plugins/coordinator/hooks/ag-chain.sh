#!/usr/bin/env bash
# Antigravity only: run several coordinator hooks for one event on the same input and print one
# answer, since one event runs one command. Usage: ag-chain.sh stop|prompt|post <hook.sh> [arg]...
#   stop    the first hook that blocks ("decision":"continue") wins; else the first that gives a
#           reason; else {"decision":"stop"}
#   prompt  the injectSteps of every hook, in order; {} when none has any
#   post    (PostToolUse) the first answer other than {}; else {}
# Hooks are given as "<name>.sh[:<arg>]" (rotation-guard.sh:stop). A hook that fails or prints
# nothing is skipped.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
kind="${1:-}"; shift || true
input="$(cat)"
outs=()
for h in "$@"; do
  name="${h%%:*}"; arg=""; [[ "$h" == *:* ]] && arg="${h#*:}"
  [[ "$name" =~ ^[a-z-]+\.sh$ && -f "$here/$name" ]] || continue
  o="$(printf '%s' "$input" | bash "$here/$name" $arg 2>/dev/null)" || o=""
  o="$(printf '%s' "$o" | tr -d '\n')"
  [[ -n "$o" ]] && outs+=("$o")
done
if [[ "$kind" == stop ]]; then
  for o in ${outs[@]+"${outs[@]}"}; do [[ "$o" == *'"decision":"continue"'* ]] && { printf '%s\n' "$o"; exit 0; }; done
  for o in ${outs[@]+"${outs[@]}"}; do [[ "$o" == *'"reason":'* ]] && { printf '%s\n' "$o"; exit 0; }; done
  printf '{"decision":"stop"}\n'
elif [[ "$kind" == post ]]; then
  for o in ${outs[@]+"${outs[@]}"}; do [[ "$o" != '{}' ]] && { printf '%s\n' "$o"; exit 0; }; done
  printf '{}\n'
else
  steps=""
  for o in ${outs[@]+"${outs[@]}"}; do
    [[ "$o" == '{"injectSteps":['*']}' ]] || continue
    s="${o#'{"injectSteps":['}"; s="${s%']}'}"
    steps="${steps:+$steps,}$s"
  done
  if [[ -n "$steps" ]]; then printf '{"injectSteps":[%s]}\n' "$steps"; else printf '{}\n'; fi
fi
