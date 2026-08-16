#!/usr/bin/env bats

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

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

@test "Cleans up the pre-command container when hook is pre-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"

  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id-pre-command : echo 'Removed container'"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
  assert_output --partial "Removed container"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK
}

@test "Cleans up the post-command container when hook is post-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"

  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id-post-command : echo 'Removed container'"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
  assert_output --partial "Removed container"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK
}

@test "Cleans up the post-command tmpdir marker, leaving the command hook's alone" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  post_tmpdir=$(mktemp -d)
  command_tmpdir=$(mktemp -d)
  post_marker="/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}-post-command.tmpdir"
  command_marker="/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
  echo "$post_tmpdir" > "$post_marker"
  echo "$command_tmpdir" > "$command_marker"

  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id-post-command : true"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
  [[ ! -d "$post_tmpdir" ]]
  [[ ! -f "$post_marker" ]]
  [[ -d "$command_tmpdir" ]]
  [[ -f "$command_marker" ]]

  rm -rf "$command_tmpdir" "$command_marker"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK
}

@test "Succeeds even when container doesn't exist" {
  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id : exit 1"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
}

@test "Cleans up docker_from_docker tmpdir when marker file exists" {
  real_tmpdir=$(mktemp -d)
  marker_file="/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
  echo "$real_tmpdir" > "$marker_file"

  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
  [[ ! -d "$real_tmpdir" ]]
  [[ ! -f "$marker_file" ]]
}

@test "pre-exit succeeds when no docker_from_docker marker file exists" {
  stub docker \
    "rm -f docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/pre-exit"

  assert_success
}
