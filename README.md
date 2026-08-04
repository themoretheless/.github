# Shared GitHub workflows

Reusable workflows and composite actions for repositories owned by [`@themoretheless`](https://github.com/themoretheless).

Triggers and `concurrency` always remain in the calling repository.

## Copilot pull request review

Keep the event and caller permissions in each project, then delegate the review job to the shared workflow:

```yaml
name: Copilot pull request review

on:
  pull_request_target:
    types: [opened, reopened, synchronize, ready_for_review]

jobs:
  copilot-review:
    if: >-
      github.event.pull_request.draft == false &&
      github.event.pull_request.head.repo.full_name == github.repository
    permissions:
      contents: read
      pull-requests: write
    uses: themoretheless/.github/.github/workflows/copilot-review.yml@v1
    with:
      fail_on_comments: true
```

The same-repository, non-draft check is repeated inside the reusable workflow as defense in depth. Both `pull_request` and `pull_request_target` callers are supported. The example uses `pull_request_target` so the token can request a review, but neither the caller nor the shared workflow checks out or executes pull request code. The called workflow uses the caller's event and `github.token`; the caller must grant the permissions shown above. It fixes the runner and job timeout centrally while forwarding `pull_request_number`, `timeout_seconds`, `poll_interval_seconds`, and `fail_on_comments` to the underlying action. When supplied, `pull_request_number` must match the caller event's pull request.

`fail_on_comments` defaults to `false`. The workflow also outputs `review_id`, `review_url`, `comments_count`, and `has_feedback`. Copilot reviews are comments rather than approvals, so enable `fail_on_comments` when the CI job should act as a merge gate.

## Deploy GitHub Pages

Each project builds its own site and uploads a Pages artifact. The shared workflow performs only the deployment:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: read
    steps:
      - uses: actions/checkout@v7
      - uses: actions/configure-pages@v6

      # Build the static site into dist/ here.

      - uses: actions/upload-pages-artifact@v5
        with:
          path: dist

  deploy:
    needs: build
    permissions:
      pages: write
      id-token: write
    uses: themoretheless/.github/.github/workflows/deploy-github-pages.yml@v1
```

If the uploaded artifact has a custom name, pass `artifact_name` with `with:`.

## Set up Vue and Rust/WebAssembly

Use the Vue action and configure the generic Rust action with the required targets and tools. Checkout must run first:

```yaml
steps:
  - uses: actions/checkout@v7

  - uses: themoretheless/.github/.github/actions/setup-vue@v1
    with:
      node-version-file: playground/.nvmrc
      npm-cache-dependency-path: playground/package-lock.json
      working-directory: playground

  - uses: themoretheless/.github/.github/actions/setup-rust@v1
    with:
      rust-toolchain: beta
      targets: wasm32-unknown-unknown
      tools: wasm-pack@0.14.0,wasm-bindgen-cli@0.2.126
      cargo-workspaces: "wasm -> target"

  - run: npm --prefix playground run build:pages
```

Project-specific dependency installation, tests, and build commands intentionally remain in the caller.

Set either `node-version` or `node-version-file`. When `node-version-file` is present, it takes precedence over the action's default `node-version`; the path is relative to the repository root.

## Configure Dependabot for GitHub Actions, npm, Rust and .NET

Copy the shared template into a repository's `.github` directory:

```bash
mkdir -p .github
curl -fsSL \
  https://raw.githubusercontent.com/themoretheless/.github/main/templates/dependabot/npm-rust-dotnet.yml \
  -o .github/dependabot.yml
```

The template checks GitHub Actions, npm, Cargo and NuGet dependencies weekly and
groups each ecosystem into its own pull request. All manifests are assumed to be
rooted at `/`; adjust the corresponding `directory` when a project keeps a
manifest in a subdirectory such as `/wasm` or `/src`.

## Set up Rust

The generic Rust composite action installs an optional toolchain, components, targets, and Cargo tools, prints tool versions, and configures the Cargo cache. It uses the official `actions/cache` action and installs tools directly with `cargo install --locked`; pin tool specs as `package@version` for reproducible CI:

```yaml
steps:
  - uses: actions/checkout@v7
  - uses: themoretheless/.github/.github/actions/setup-rust@v1
    with:
      rust-toolchain: beta
      components: rustfmt,clippy
      tools: cargo-deny@0.20.2
      cargo-workspaces: ". -> target"
```

## Resolve a Cargo package version

The version action selects a package from a Cargo workspace and exposes its version, tag, and SemVer prerelease status:

```yaml
- id: package
  uses: themoretheless/.github/.github/actions/cargo-package-version@v1
  with:
    package-name: themoretheless-tokenizer

- if: steps.package.outputs.prerelease == 'true'
  run: echo "Preview ${{ steps.package.outputs.tag }}"
```

Use the release validation action to enforce branch policy and optional explicit confirmation:

```yaml
- uses: themoretheless/.github/.github/actions/validate-package-release@v1
  with:
    version: ${{ steps.package.outputs.version }}
    tag: ${{ steps.package.outputs.tag }}
    prerelease: ${{ steps.package.outputs.prerelease }}
    confirmation: ${{ inputs.confirmation }}
```

The tag validation action makes release workflows safely repeatable and rejects an existing tag that points to another commit:

```yaml
- id: tag
  uses: themoretheless/.github/.github/actions/validate-release-tag@v1
  with:
    tag: ${{ steps.package.outputs.tag }}
```

After validation, create the annotated tag and GitHub Release with:

```yaml
- uses: themoretheless/.github/.github/actions/create-github-release@v1
  with:
    tag: ${{ steps.package.outputs.tag }}
    prerelease: ${{ steps.package.outputs.prerelease }}
    tag-exists: ${{ steps.tag.outputs.exists }}
    github-token: ${{ github.token }}
    release-name: Release ${{ steps.package.outputs.tag }}
    files: |
      dist/*.tar.gz
      native-artifacts/**/*
    fail-on-unmatched-files: true
```

Validate or publish a Cargo package with the same action:

```yaml
- uses: themoretheless/.github/.github/actions/publish-crate@v1
  with:
    package-name: themoretheless-tokenizer
    dry-run: true

- uses: themoretheless/.github/.github/actions/publish-crate@v1
  with:
    package-name: themoretheless-tokenizer
    registry-token: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

## Release a Rust library

This reusable workflow watches the caller's push event, compares the Cargo package version with the previous commit, runs release checks, then creates an annotated `v{version}` tag and a GitHub Release:

```yaml
name: Release

on:
  push:
    branches: [main]
    paths:
      - Cargo.toml
      - Cargo.lock

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    permissions:
      contents: write
    uses: themoretheless/.github/.github/workflows/release-rust-library.yml@v1
```

No release is created when the Cargo version is unchanged. Re-running a partially completed release is safe when the existing tag points to the same commit. The default toolchain is `beta`; set `rust_toolchain` explicitly when a library must enforce another MSRV.

For a package inside a workspace, identify it explicitly:

```yaml
    with:
      manifest_path: crates/tokenizer/Cargo.toml
      package_name: themoretheless-tokenizer
      cargo_workspaces: "crates/tokenizer -> target"
```

This workflow creates a GitHub tag and Release only; it does not publish to crates.io.

## Versioning

- `@v1` follows backward-compatible updates in the current major version.
- `@v1.2.0` pins this release.
- Use a full commit SHA when the caller requires an immutable reference.

The doubled `.github/.github` in `uses` paths is intentional: the first `.github` is the repository name, and the second is its workflows or actions directory.
