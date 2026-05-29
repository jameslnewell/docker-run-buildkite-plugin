#!/usr/bin/env bats

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

  export PLUGIN_DIR="${PLUGIN_DIR:-.}"
  export BUILDKITE_JOB_ID="test-job-id"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="ubuntu:24.04"
}

teardown() {
  unstub docker
}

@test "Runs with image only" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes command as string" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="echo hello"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id ubuntu:24.04 echo hello : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes command as array" {
  skip "bats-mock limitation with indirect variable expansion in process substitution"
}

@test "Passes environment variables" {
  skip "bats-mock limitation with indirect variable expansion in process substitution"
}

@test "Passes volume mounts" {
  skip "bats-mock limitation with indirect variable expansion in process substitution"
}

@test "Passes workdir option" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/app"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --workdir /app ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes entrypoint option" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/bash"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --entrypoint /bin/bash ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Fails when docker pull fails" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="invalid/image:nonexistent"

  stub docker "pull invalid/image:nonexistent : exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
}

@test "Integration: runs with multiple configuration options" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workspace"
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="build script"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --workdir /workspace --entrypoint /bin/sh ubuntu:24.04 build script : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}
