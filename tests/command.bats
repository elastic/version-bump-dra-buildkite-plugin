#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Uncomment to enable stub debugging
  # export CURL_STUB_DEBUG=/dev/tty

  # Backstop only. Every stubbed test below is written to terminate on its own;
  # this just stops a mis-specified stub from hanging a CI agent for hours,
  # since the polling loop has no bound of its own.
  export BATS_TEST_TIMEOUT=30

  # The argument list every stub matches on, up to but not including the URL.
  # Kept in one place so a change to the curl flags is a one-line edit here
  # rather than an edit to every stub below.
  CURL_MATCH="-sSL --connect-timeout 10 --max-time 60 -w *"

  STAGING="https://artifacts-staging.elastic.co/beats/latest/9.5.json"
  SNAPSHOT="https://artifacts-snapshot.elastic.co/beats/latest/9.5.json"
  MASTER="https://artifacts-snapshot.elastic.co/beats/latest/master.json"
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

@test "Invalid polling_interval fails before any polling starts" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  # 0 is the dangerous one: sleep 0 returns immediately, so the loop would
  # hammer the DRA endpoints for the full job timeout.
  # An empty value is not listed: ${VAR:-60} substitutes the default for null
  # as well as unset, so it is a valid fall-through to 60 rather than an error.
  for invalid in 0 00 -5 abc; do
    export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="$invalid"

    run "$PWD"/hooks/command

    assert_failure
    assert_output --partial "'polling_interval' must be a positive whole number of seconds"
  done
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
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.3\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.3-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "latest/9.5.json"
  refute_output --partial "9.5.3.json"

  unstub curl
}

@test "Workflow patch builds only the two release-branch checks" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'"

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
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${MASTER} : printf '%s\n200\n' '{\"version\":\"9.6.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "master.json == 9.6.0-SNAPSHOT"
  assert_output --partial "✓ All 3 checks passed"

  unstub curl
}

@test "Workflow minor rejects a version that is not a X.Y.0 release" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="minor"

  # Both would otherwise be accepted and watch a plausible but wrong set of
  # manifests: 9.5 for the release branch, 9.6.0-SNAPSHOT for main.
  for invalid in 9.5.5 9.5.9; do
    export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="$invalid"

    run "$PWD"/hooks/command

    assert_failure
    assert_output --partial "'workflow' is 'minor' but 'version' is not a X.Y.0 release, got '${invalid}'"
  done
}

@test "Workflow patch accepts a non-zero patch component" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.9"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.9\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.9-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  refute_output --partial "master.json"

  unstub curl
}

@test "Workflow patch rejects a X.Y.0 release" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  # X.Y.0 is a minor. Accepted here it would watch the right two manifests but
  # skip the main-branch check, which is the gap the plugin exists to close.
  for invalid in 9.5.0 9.5.00; do
    export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="$invalid"

    run "$PWD"/hooks/command

    assert_failure
    assert_output --partial "'workflow' is 'patch' but 'version' is a X.Y.0 release, got '${invalid}'"
  done
}

@test "Default polling interval of 60s is used when omitted" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Polling every 60s"

  unstub curl
}

@test "Custom polling interval is respected" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="5"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Polling every 5s"

  unstub curl
}

@test "All checks matching on the first poll exits successfully" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "✓ staging (9.5): 9.5.4 (matches!)"
  assert_output --partial "✓ All 2 checks passed"

  unstub curl
}

@test "Polling continues until a lagging artifact catches up" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  # The snapshot is stubbed only once: it matches on the first poll, so the
  # second poll must fetch the lagging staging URL alone. unstub fails if any
  # queued response goes unused, which is what proves it is not re-fetched.
  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.3\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "staging (9.5): found 9.5.3 (expected 9.5.4)"
  assert_output --partial "✓ All 2 checks passed"

  unstub curl
}

@test "A non-200 response is reported as an HTTP status" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n404\n' 'Not Found'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "❌ staging (9.5): HTTP status 404"
  refute_output --partial "every manifest returned HTTP 404"

  unstub curl
}

@test "Every manifest returning 404 on the first poll fails fast" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  # Only one round is stubbed. unstub fails on a queued response that goes
  # unused, and the stub itself fails on an unexpected call, so this is what
  # proves the loop exits rather than sleeping and polling again.
  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n404\n' 'Not Found'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n404\n' 'Not Found'"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "every manifest returned HTTP 404 on the first poll"
  assert_output --partial "got 'beats'"

  unstub curl
}

@test "Workflow minor keeps polling when only the new release branch 404s" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.0"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="minor"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  # The legitimate case a blanket 404 rule would break: a freshly cut release
  # branch has published nothing yet, so both branch manifests 404 while main
  # is already live. Not every check 404s, so this must keep polling.
  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n404\n' 'Not Found'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n404\n' 'Not Found'" \
    "${CURL_MATCH} ${MASTER} : printf '%s\n200\n' '{\"version\":\"9.6.0-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.0\"}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.0-SNAPSHOT\"}'"

  run "$PWD"/hooks/command

  assert_success
  refute_output --partial "every manifest returned HTTP 404"
  assert_output --partial "✓ All 3 checks passed"

  unstub curl
}

@test "A manifest without a version field is reported as a missing field" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "❌ staging (9.5): Field not found in JSON"

  unstub curl
}

@test "A 200 carrying a non-JSON body is reported as invalid JSON" {
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_PRODUCT="beats"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_VERSION="9.5.4"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_WORKFLOW="patch"
  export BUILDKITE_PLUGIN_VERSION_BUMP_DRA_POLLING_INTERVAL="1"

  # A truncated manifest or an error page served with a 200. This must not be
  # reported as a connection error, which would send anyone debugging it
  # looking at the network instead of at the artifact.
  stub curl \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{invalid}'" \
    "${CURL_MATCH} ${SNAPSHOT} : printf '%s\n200\n' '{\"version\":\"9.5.4-SNAPSHOT\"}'" \
    "${CURL_MATCH} ${STAGING} : printf '%s\n200\n' '{\"version\":\"9.5.4\"}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "❌ staging (9.5): Response is not valid JSON"
  refute_output --partial "Connection error"

  unstub curl
}
