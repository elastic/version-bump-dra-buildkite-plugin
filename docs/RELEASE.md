# Release Process

This plugin uses [Release Drafter](https://github.com/release-drafter/release-drafter) to prepare semantic-versioned GitHub releases.

## Versioning

Every pull request must have exactly one `changelog:*` label. Release Drafter uses these labels to group changes and select the next version:

- `changelog:breaking` selects a major version bump.
- `changelog:feature` selects a minor version bump.
- All other included labels use the default patch version bump.
- `changelog:skip` excludes a pull request from the release notes; it does not override the default version increment.

The release tag is `vMAJOR.MINOR.PATCH`. The [Release Drafter configuration](../.github/release-drafter.yml) defines the categories and version rules.

## Publishing a release

1. Add exactly one changelog label to each pull request, then merge it to `main`.
2. The [release-drafter workflow](../.github/workflows/release-drafter.yml) updates the draft release.
3. Review the draft notes and proposed version in [GitHub Releases](https://github.com/elastic/version-bump-dra-buildkite-plugin/releases), then publish the release.
4. The [version bump workflow](../.github/workflows/bump-readme-version.yml) opens a pull request updating the plugin tag used in the README examples. Review and merge that pull request.

The repository's Actions settings must allow workflows to create pull requests for the automated version update.

## Changelog labels

| Label | Use |
| --- | --- |
| `changelog:breaking` | Breaking changes; major version |
| `changelog:feature` | New features; minor version |
| `changelog:enhancement` | Improvements to existing behavior |
| `changelog:fix` | Bug fixes |
| `changelog:docs` | Documentation changes |
| `changelog:chore` | Maintenance |
| `changelog:ci` | CI/CD changes |
| `changelog:dependencies` | Dependency updates |
| `changelog:skip` | Exclude the pull request from release notes |
