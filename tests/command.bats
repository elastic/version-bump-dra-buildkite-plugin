#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Uncomment to enable stub debugging
  # export CURL_STUB_DEBUG=/dev/tty

  # Backstop only. Every stubbed test below is written to terminate on its own;
  # this just stops a mis-specified stub from hanging a CI agent for hours,
  # since the polling loop has no bound of its own.
  export BATS_TEST_TIMEOUT=30

  STAGING="https://artifacts-staging.elastic.co/beats/latest/9.5.json"
  SNAPSHOT="https://storage.googleapis.com/elastic-artifacts-snapshot/beats/latest/9.5.json"
  MASTER="https://storage.googleapis.com/elastic-artifacts-snapshot/beats/latest/master.json"
}

# Every stubbed test queues a final response that matches the expected value, so
# the polling loop reaches its exit condition rather than sleeping forever.

@test "Missing product parameter fails" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'product' parameter is required"
}

@test "Missing version parameter fails" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'version' parameter is required"
}

@test "Missing workflow parameter fails" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'workflow' parameter is required"
}

@test "Invalid workflow value fails" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="rollback"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'workflow' must be 'patch' or 'minor', got 'rollback'"
}

@test "Workflow major is not supported and fails" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="major"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'workflow' must be 'patch' or 'minor', got 'major'"
}

@test "Non-semver version fails even for the patch workflow" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "'version' must be MAJOR.MINOR.PATCH, got '9.5'"
}

@test "Release branch is derived from version, dropping the patch component" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.3"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.3\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.3-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "latest/9.5.json"
  refute_output --partial "9.5.3.json"

  unstub curl
}

@test "Workflow patch builds only the two release-branch checks" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "staging (9.5)"
  assert_output --partial "snapshot (9.5)"
  refute_output --partial "master.json"

  unstub curl
}

@test "Workflow minor adds a main-branch check at the next dev minor" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="minor"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'" \
    "-sSL -w * ${MASTER} : printf '%s\n200\n' '{\"version\":\"9.6.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "master.json == 9.6.0-SNAPSHOT"
  assert_output --partial "✓ All 3 checks passed"

  unstub curl
}

@test "Workflow minor resets the patch component when bumping" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.9"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="minor"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.9\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.9-SNAPSHOT\"}'" \
    "-sSL -w * ${MASTER} : printf '%s\n200\n' '{\"version\":\"9.6.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "master.json == 9.6.0-SNAPSHOT"
  refute_output --partial "9.5.10"

  unstub curl
}

@test "Default polling interval of 60s is used when omitted" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Polling every 60s"

  unstub curl
}

@test "Custom polling interval is respected" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="5"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Polling every 5s"

  unstub curl
}

@test "All checks matching on the first poll exits successfully" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "✓ staging (9.5): 9.5.0 (matches!)"
  assert_output --partial "✓ All 2 checks passed"

  unstub curl
}

@test "Polling continues until a lagging artifact catches up" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  # The snapshot is stubbed only once: it matches on the first poll, so the
  # second poll must fetch the lagging staging URL alone. unstub fails if any
  # queued response goes unused, which is what proves it is not re-fetched.
  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.4.0\"}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'" \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "staging (9.5): found 9.4.0 (expected 9.5.0)"
  assert_output --partial "✓ All 2 checks passed"

  unstub curl
}

@test "A non-200 response is reported as an HTTP status" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n404\n' 'Not Found'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'" \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "❌ staging (9.5): HTTP status 404"

  unstub curl
}

@test "A manifest without a version field is reported as a missing field" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  stub curl \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{}'" \
    "-sSL -w * ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'" \
    "-sSL -w * ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "❌ staging (9.5): Field not found in JSON"

  unstub curl
}
