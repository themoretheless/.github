# Shared GitHub workflows

Reusable workflows for repositories owned by [`@themoretheless`](https://github.com/themoretheless).

## Deploy GitHub Pages

Each project keeps its own build steps (Node.js, Rust/WASM, or anything else). This repository owns only the common deployment step.

The caller must build the site and upload a Pages artifact before invoking the reusable workflow:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v6

      # Build the static site into dist/ here.

      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v4
        with:
          path: dist

  deploy:
    needs: build
    permissions:
      pages: write
      id-token: write
    uses: themoretheless/.github/.github/workflows/deploy-pages.yml@v1
```

If the uploaded artifact has a custom name, pass it explicitly:

```yaml
    with:
      artifact_name: my-pages-artifact
```

The doubled `.github/.github` in the `uses` path is intentional: the first is the repository name, the second is its workflows directory.
