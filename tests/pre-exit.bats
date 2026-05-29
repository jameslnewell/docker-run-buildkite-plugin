#!/usr/bin/env bats

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"

  export PLUGIN_DIR="${PLUGIN_DIR:-.}"
  export BUILDKITE_JOB_ID="test-job-id"
}

teardown() {
  unstub docker
}

@test "Cleans up container with correct name" {
  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id : echo 'Removed container'"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
  assert_output --partial "Removed container"
}

@test "Succeeds even when container doesn't exist" {
  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id : exit 1"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
}
