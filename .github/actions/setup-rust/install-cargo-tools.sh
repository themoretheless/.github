#!/usr/bin/env bash

set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

remaining=${TOOLS:-}
while :; do
  case "$remaining" in
    *,*)
      tool=${remaining%%,*}
      remaining=${remaining#*,}
      ;;
    *)
      tool=$remaining
      remaining=""
      ;;
  esac

  tool=$(trim "$tool")
  if [[ -n "$tool" ]]; then
    if [[ "$tool" == -* || "$tool" == *[[:space:]]* ]]; then
      echo "Invalid Cargo package spec: $tool" >&2
      exit 1
    fi

    cargo install --locked "$tool"
  fi

  [[ -n "$remaining" ]] || break
done
