#!/usr/bin/env bats

setup() {
  export PLUGIN_PATH="${BATS_TEST_DIRNAME}/.."
  export BUILDKITE_JOB_ID="docker-run-test-$$"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="busybox:latest"
}

teardown() {
  docker rm -f "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}" 2>/dev/null || true
}

skip_if_no_docker() {
  if ! command -v docker &>/dev/null; then
    skip "Docker is not available"
  fi
}

@test "integration: runs simple command in container" {
  skip_if_no_docker

  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="echo success"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"success"* ]]
}

@test "integration: respects working directory" {
  skip_if_no_docker

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/tmp"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="pwd"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == */tmp* ]]
}

@test "integration: passes environment variables" {
  skip_if_no_docker

  export BUILDKITE_PLUGIN_DOCKER_RUN_ENV_0="TEST_VAR=hello"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="sh -c 'echo \$TEST_VAR'"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"hello"* ]]
}

@test "integration: cleans up container after execution" {
  skip_if_no_docker

  bash "$PLUGIN_PATH/hooks/command" 2>/dev/null || true
  bash "$PLUGIN_PATH/hooks/pre-exit" 2>/dev/null || true

  # Container should not exist after cleanup
  run docker inspect "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}"
  [[ $status -ne 0 ]]
}

@test "integration: handles command failure gracefully" {
  skip_if_no_docker

  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="exit 1"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -ne 0 ]]
}
