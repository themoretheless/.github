# Create GitHub release

Creates and pushes an annotated tag when needed, then creates a GitHub Release
with generated notes. Existing releases are kept and matching assets are
re-uploaded with `gh release upload --clobber`.

```yaml
- uses: themoretheless/.github/.github/actions/create-github-release@<commit-sha>
  with:
    tag: ${{ needs.metadata.outputs.tag }}
    prerelease: ${{ needs.metadata.outputs.prerelease }}
    tag-exists: ${{ needs.metadata.outputs.tag-exists }}
    github-token: ${{ github.token }}
    release-name: Release ${{ needs.metadata.outputs.tag }}
    files: |
      web-${{ needs.metadata.outputs.tag }}.tar
      native-artifacts/**/*
    fail-on-unmatched-files: true
```

`files` accepts one path or glob pattern per line. `**` matches recursively.
Patterns are expanded before the tag is created; with
`fail-on-unmatched-files: true` (the default), any unmatched pattern stops the
action without pushing a tag. Spaces inside paths are preserved.
