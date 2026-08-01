# Shared GitHub workflows

Reusable workflows and composite actions for repositories owned by [`@themoretheless`](https://github.com/themoretheless).

Triggers and `concurrency` always remain in the calling repository.

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
    uses: themoretheless/.github/.github/workflows/deploy-pages.yml@v1
```

If the uploaded artifact has a custom name, pass `artifact_name` with `with:`.

## Set up Rust and WebAssembly

The composite action installs Node.js, Rust/WASM targets and pinned WebAssembly tools, and configures npm and Cargo caches. Checkout must run first:

```yaml
steps:
  - uses: actions/checkout@v7

  - uses: themoretheless/.github/.github/actions/setup-rust-web@v1
    with:
      node-version: "22.13.0"
      rust-version: "1.96.0"
      cargo-workspaces: "wasm -> target"

  - run: npm ci
  - run: cargo fetch --manifest-path wasm/Cargo.toml --locked
  - run: npm run build:pages
```

Project-specific dependency installation, tests, and build commands intentionally remain in the caller.

## Run Rust CI

The reusable CI checks formatting and Clippy on one runner and runs tests on a configurable runner matrix:

```yaml
jobs:
  rust:
    permissions:
      contents: read
    uses: themoretheless/.github/.github/workflows/rust-ci.yml@v1
    with:
      working_directory: backend
      rust_toolchain: "1.96.0"
      test_runners: '["ubuntu-latest", "macos-latest", "windows-latest"]'
      clippy_args: "--workspace --all-targets --locked"
      test_args: "--workspace --no-fail-fast --locked"
```

Android, iOS, and WASM packaging stay in platform-specific workflows; this workflow checks the shared host-side Rust code.

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

No release is created when the Cargo version is unchanged. Re-running a partially completed release is safe when the existing tag points to the same commit. The default toolchain is `stable`; set `rust_toolchain` explicitly to enforce the library's MSRV.

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
