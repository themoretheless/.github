#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_boolean() {
  local name=$1
  local value=$2
  if [[ "$value" != "true" && "$value" != "false" ]]; then
    fail "${name} must be 'true' or 'false', got '${value}'"
  fi
}

: "${GH_TOKEN:?Error: github-token must not be empty}"
: "${TAG:?Error: tag must not be empty}"
: "${REMOTE:?Error: remote must not be empty}"
: "${GITHUB_OUTPUT:?Error: GITHUB_OUTPUT must be set}"

ACTION_PATH=${ACTION_PATH:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}
FAIL_ON_UNMATCHED_FILES=${FAIL_ON_UNMATCHED_FILES:-true}
FILES=${FILES:-}
PRERELEASE=${PRERELEASE:-false}
RELEASE_NAME=${RELEASE_NAME:-}
TAG_EXISTS=${TAG_EXISTS:-false}

require_boolean prerelease "$PRERELEASE"
require_boolean tag-exists "$TAG_EXISTS"
require_boolean fail-on-unmatched-files "$FAIL_ON_UNMATCHED_FILES"

command -v python3 >/dev/null 2>&1 || fail "python3 is required to expand release assets"
command -v git >/dev/null 2>&1 || fail "git is required to create and push release tags"
command -v gh >/dev/null 2>&1 || fail "gh is required to create GitHub Releases"

# Validate every asset pattern before creating a tag. A typo should not leave a
# pushed tag behind when fail-on-unmatched-files is enabled.
asset_list=$(mktemp)
cleanup() {
  rm -f "$asset_list"
}
trap cleanup EXIT

python3 "${ACTION_PATH}/collect-assets.py" \
  --patterns "$FILES" \
  --fail-on-unmatched-files "$FAIL_ON_UNMATCHED_FILES" >"$asset_list"

assets=()
while IFS= read -r -d '' asset; do
  assets+=("$asset")
done <"$asset_list"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if [[ "$TAG_EXISTS" != "true" ]]; then
  git tag -a -m "Release $TAG" -- "$TAG"
  git push -- "$REMOTE" "refs/tags/$TAG"
fi

title=${RELEASE_NAME:-$TAG}
release_flags=(--verify-tag --generate-notes --title "$title")
if [[ "$PRERELEASE" == "true" ]]; then
  release_flags+=(--prerelease)
fi

if gh release view -- "$TAG" >/dev/null 2>&1; then
  if ((${#assets[@]} > 0)); then
    gh release upload --clobber -- "$TAG" "${assets[@]}"
  fi
else
  if ((${#assets[@]} > 0)); then
    gh release create "${release_flags[@]}" -- "$TAG" "${assets[@]}" >/dev/null
  else
    # Bash 3.2 treats an expanded empty array as an unbound variable under
    # `set -u`, so keep the no-asset invocation separate.
    gh release create "${release_flags[@]}" -- "$TAG" >/dev/null
  fi
fi

url=$(gh release view --json url --jq .url -- "$TAG")
printf 'url=%s\n' "$url" >>"$GITHUB_OUTPUT"
echo "Release: ${url}"
