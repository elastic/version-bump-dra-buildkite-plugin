# Version Bump DRA Buildkite Plugin

A Buildkite plugin that polls until a product's Daily Release Artifacts (DRA) have been published at the version you are bumping to.

The DRA URL conventions, the manifest field, and the version arithmetic are all built in, so a pipeline only needs to say which product it is, which version it is moving to, and which kind of bump is happening. The plugin works out which manifests to watch and what each one should say.

## Requirements

- `curl`
- `jq`

## Features

- Derives the release branch from the version, so it never has to be passed separately
- Polls the staging and snapshot manifests for that branch
- For a minor bump, additionally waits for `main` to move on to the next development minor
- Reports each check separately on every poll, so a slow artifact is easy to spot
- Idempotent: if the manifests already report the expected version, the first poll succeeds and the step exits immediately

## Example

```yaml
steps:
  - label: "Wait for DRA artifacts"
    plugins:
      - elastic/version-bump-dra#v1.0.0:
          product: "beats"
          version: "9.5.0"
          workflow: "minor"
```

In the centralized version-bump pipeline, `version` and `workflow` are not hardcoded — they come from the `NEW_VERSION` and `WORKFLOW` environment variables the pipeline already provides.

This produces:

```bash
~~~ :package: Version Bump DRA
Product: beats
Version: 9.5.0
Workflow: minor
Polling every 60s

Check: staging (9.5) -> https://artifacts-staging.elastic.co/beats/latest/9.5.json == 9.5.0
Check: snapshot (9.5) -> https://storage.googleapis.com/elastic-artifacts-snapshot/beats/latest/9.5.json == 9.5.0-SNAPSHOT
Check: snapshot (main, next minor) -> https://storage.googleapis.com/elastic-artifacts-snapshot/beats/latest/master.json == 9.6.0-SNAPSHOT

  ✓ staging (9.5): 9.5.0 (matches!)
  ✓ snapshot (9.5): 9.5.0-SNAPSHOT (matches!)
  ✓ snapshot (main, next minor): 9.6.0-SNAPSHOT (matches!)

✓ All 3 checks passed
```

### Required input

| input      | description                                                                                                                                                                              |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `product`  | DRA product name as it appears in the artifact path, for example `beats` or `apm-server`. This is not always identical to the repository name.                                           |
| `version`  | The full `MAJOR.MINOR.PATCH` version being bumped to, for example `9.5.0`. The release branch is derived from this by dropping the patch component, so `9.5.3` watches the `9.5` branch. |
| `workflow` | One of `patch` or `minor`. Determines which checks run.                                                                                                                                  |

The `workflow` value selects the checks:

| workflow | checks performed                                                                                                                          |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `patch`  | staging and snapshot on the release branch                                                                                                |
| `minor`  | staging and snapshot on the release branch, **plus** the snapshot manifest on `main`, which must have moved to the next development minor |

Only `minor` bumps move `main`, which is why it is the only workflow with a third check.

`major` is not supported yet. Passing it fails the step rather than falling back to the `patch` checks, since a major bump has different expectations for what the manifests should report.

### Optional input

| input              | default | description                    |
| ------------------ | ------- | ------------------------------ |
| `polling_interval` | `60`    | Seconds to wait between polls. |

The plugin polls until every check passes. It has no timeout of its own — the step is bounded by the Buildkite job timeout.

## Use Cases

### 1. Wait for a patch bump to publish

Two checks: the staging and snapshot manifests for the `9.5` branch must both report `9.5.4`.

```yaml
steps:
  - label: "Wait for DRA artifacts"
    plugins:
      - elastic/version-bump-dra#v1.0.0:
          product: "beats"
          version: "9.5.4"
          workflow: "patch"
```

### 2. Wait for a minor bump, including main

Three checks. As well as the `9.5` branch reporting `9.5.0`, the snapshot manifest on `main` must report `9.6.0-SNAPSHOT`, confirming development has moved on to the next minor.

```yaml
steps:
  - label: "Wait for DRA artifacts"
    plugins:
      - elastic/version-bump-dra#v1.0.0:
          product: "beats"
          version: "9.5.0"
          workflow: "minor"
          polling_interval: 120
```

## Development

This repository is using `pre-commit` to automate commit hooks.

It also uses `hermit` to automate provisioning of the tools required to interact with the repo. Run `. bin/activate-hermit` to activate it in your shell. This includes all the tools in the `bin`.

Before your first commit, please run `pre-commit install` inside the repository directory to set up the git hook scripts.

### Running tests locally

Runs the bats suite directly, installing bats and its helper libraries into a temporary directory:

```bash
./run_test.sh
```

Runs the plugin-linter against the plugin:

```bash
docker run -it --rm -v "$PWD:/plugin:ro" buildkite/plugin-linter --id elastic/version-bump-dra
```

Runs the plugin-tester against the command.bats:

```bash
docker run -it --rm -v "$PWD:/plugin:ro" buildkite/plugin-tester:v4.3.0
```
