#!/usr/bin/env bash

set -euo pipefail

action_dir=$(cd "$(dirname "$0")" && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/setup-rust-test.XXXXXX")
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2

  grep -F -- "$expected" "$file" >/dev/null || fail "$file does not contain: $expected"
}

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/workspace/crate"

cat > "$test_root/bin/cargo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CARGO_CALLS"
EOF

cat > "$test_root/bin/rustc" <<'EOF'
#!/usr/bin/env bash
cat <<'VERSION'
rustc 1.99.0-beta.1 (123456789 2099-01-01)
binary: rustc
commit-hash: 1234567890abcdef1234567890abcdef12345678
commit-date: 2099-01-01
host: x86_64-unknown-linux-gnu
release: 1.99.0-beta.1
LLVM version: 99.0.0
VERSION
EOF

chmod +x "$test_root/bin/cargo" "$test_root/bin/rustc"

export CARGO_CALLS="$test_root/cargo-calls"
export PATH="$test_root/bin:$PATH"

TOOLS=" wasm-pack@0.15.0, cargo-deny@0.18.3 , " \
  bash "$action_dir/install-cargo-tools.sh"

assert_contains "$CARGO_CALLS" "install --locked wasm-pack@0.15.0"
assert_contains "$CARGO_CALLS" "install --locked cargo-deny@0.18.3"
[[ $(wc -l < "$CARGO_CALLS" | tr -d ' ') == 2 ]] || fail "unexpected cargo invocation count"

if TOOLS="--git" bash "$action_dir/install-cargo-tools.sh" >/dev/null 2>&1; then
  fail "option-like tool spec was accepted"
fi

export GITHUB_OUTPUT="$test_root/github-output"
export GITHUB_ENV="$test_root/github-env"
export HOME="$test_root/home"
export CARGO_HOME="$test_root/home/.cargo"
export CACHE_KEY="web / wasm"
export TOOLS="wasm-pack@0.15.0, cargo-deny@0.20.2"
export CARGO_WORKSPACES=". -> target
crate
/absolute/workspace -> custom-target"

(
  cd "$test_root/workspace"
  bash "$action_dir/prepare-cache.sh"
)

assert_contains "$GITHUB_OUTPUT" "$test_root/home/.cargo/bin"
assert_contains "$GITHUB_OUTPUT" "$test_root/workspace/./target"
assert_contains "$GITHUB_OUTPUT" "$test_root/workspace/crate/target"
assert_contains "$GITHUB_OUTPUT" "/absolute/workspace/custom-target"
assert_contains "$GITHUB_OUTPUT" "toolchain=1.99.0-beta.1-x86_64-unknown-linux-gnu-1234567890abcdef1234567890abcdef12345678"
assert_contains "$GITHUB_OUTPUT" "tools=wasm-pack-0.15.0-cargo-deny-0.20.2"
assert_contains "$GITHUB_OUTPUT" "scope=web-wasm"
assert_contains "$GITHUB_ENV" "CARGO_INCREMENTAL=0"

ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$action_dir/action.yml"

assert_contains "$action_dir/action.yml" \
  "uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0"
[[ $(grep -c '^[[:space:]]*uses:' "$action_dir/action.yml") == 1 ]] || \
  fail "unexpected external action reference"

echo "setup-rust tests passed"
