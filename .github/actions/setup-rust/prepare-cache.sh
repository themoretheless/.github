#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${GITHUB_ENV:?GITHUB_ENV must be set}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

sanitize_key_part() {
  local value

  value=$(printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '-')
  value=${value#-}
  value=${value%-}
  printf '%s' "$value"
}

append_path() {
  local path=$1

  if [[ -z "$cache_paths" ]]; then
    cache_paths=$path
  else
    cache_paths="$cache_paths
$path"
  fi
}

normalize_cache_path() {
  local path=$1

  if [[ "${RUNNER_OS:-}" == Windows ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$path"
  else
    printf '%s' "$path"
  fi
}

if [[ -n "${CARGO_HOME:-}" ]]; then
  cargo_home=$CARGO_HOME
  case "$cargo_home" in
    /* | [A-Za-z]:[\\/]*) ;;
    *) cargo_home="$PWD/$cargo_home" ;;
  esac
  cargo_home=$(normalize_cache_path "$cargo_home")
else
  # actions/cache expands this itself, including on Windows runners.
  cargo_home='~/.cargo'
fi

cache_paths=""
append_path "$cargo_home/bin"
append_path "$cargo_home/registry/index"
append_path "$cargo_home/registry/cache"
append_path "$cargo_home/git/db"
append_path "$cargo_home/.crates.toml"
append_path "$cargo_home/.crates2.json"

while IFS= read -r entry || [[ -n "$entry" ]]; do
  entry=$(trim "${entry%$'\r'}")
  [[ -n "$entry" ]] || continue

  case "$entry" in
    *"->"*)
      workspace=$(trim "${entry%%->*}")
      target=$(trim "${entry#*->}")
      ;;
    *)
      workspace=$entry
      target=target
      ;;
  esac

  if [[ -z "$workspace" || -z "$target" ]]; then
    echo "Invalid cargo-workspaces entry: $entry" >&2
    exit 1
  fi

  if [[ "$workspace" != /* ]]; then
    workspace="$PWD/$workspace"
  fi

  if [[ "$target" != /* ]]; then
    target="$workspace/$target"
  fi

  target=$(normalize_cache_path "$target")
  append_path "$target"
done <<< "${CARGO_WORKSPACES:-. -> target}"

rust_release=$(rustc --version --verbose | awk -F ': ' '$1 == "release" { print $2 }')
rust_host=$(rustc --version --verbose | awk -F ': ' '$1 == "host" { print $2 }')
rust_commit=$(rustc --version --verbose | awk -F ': ' '$1 == "commit-hash" { print $2 }')
toolchain=$(sanitize_key_part "$rust_release-$rust_host-$rust_commit")

if [[ -z "$toolchain" ]]; then
  echo "Could not determine the active Rust toolchain" >&2
  exit 1
fi

scope=$(sanitize_key_part "${CACHE_KEY:-default}")
scope=${scope:-default}
tools=$(sanitize_key_part "${TOOLS:-none}")
tools=${tools:-none}

delimiter="rust_cache_paths_$$"
{
  echo "paths<<$delimiter"
  printf '%s\n' "$cache_paths"
  echo "$delimiter"
  echo "toolchain=$toolchain"
  echo "tools=$tools"
  echo "scope=$scope"
} >> "$GITHUB_OUTPUT"

# Match rust-cache's build-cache behavior and avoid storing incremental artifacts.
echo "CARGO_INCREMENTAL=0" >> "$GITHUB_ENV"
