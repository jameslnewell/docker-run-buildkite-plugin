#!/usr/bin/env bats

setup() {
  export PLUGIN_PATH="${BATS_TEST_DIRNAME}/.."
  export BUILDKITE_JOB_ID="docker-run-test-$$"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="busybox:latest"
}

teardown() {
  docker rm -f "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}" 2>/dev/null || true
  docker rm -f "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}-pre-command" 2>/dev/null || true
  docker rm -f "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}-post-command" 2>/dev/null || true
}

skip_if_no_docker() {
  if ! command -v docker &>/dev/null; then
    skip "Docker is not available"
  fi
}

@test "integration: runs simple command in container" {
  skip_if_no_docker

  # `command` is an array option — as a string the hook rejects it outright with
  # "The command option must be an array". These tests were written against an
  # older API and have been failing ever since, unnoticed, because they only ever
  # ran somewhere without a docker CLI.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="echo"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="success"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"success"* ]]
}

@test "integration: respects working directory" {
  skip_if_no_docker

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/tmp"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="pwd"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == */tmp* ]]
}

@test "integration: passes environment variables" {
  skip_if_no_docker

  # ENVIRONMENT, not ENV: the option is `environment`, so the variable this test
  # used to set was one no hook has ever read.
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT_0="TEST_VAR=hello"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="-c"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2='echo $TEST_VAR'

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"hello"* ]]
}

@test "integration: cleans up container after execution" {
  skip_if_no_docker

  # Give it something to run. With no command the container falls back to the
  # image's own CMD — `sh` for busybox — and because the plugin allocates a TTY
  # that is an interactive shell with nothing on stdin, so the hook blocks forever
  # and takes the whole suite with it.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="true"

  bash "$PLUGIN_PATH/hooks/command" 2>/dev/null || true
  bash "$PLUGIN_PATH/hooks/pre-exit" 2>/dev/null || true

  # Container should not exist after cleanup
  run docker inspect "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}"
  [[ $status -ne 0 ]]
}

@test "integration: brackets a step with a pre-command and a post-command run" {
  skip_if_no_docker

  # The step keeps its own command; both plugin runs live in the same job, so
  # they would clash if the container name were keyed on the job alone.
  export BUILDKITE_COMMAND="echo the step's own command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="echo"

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="before"
  run bash "$PLUGIN_PATH/hooks/pre-command"
  [[ $status -eq 0 ]]
  [[ "$output" == *"before"* ]]

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="after"
  run bash "$PLUGIN_PATH/hooks/post-command"
  [[ $status -eq 0 ]]
  [[ "$output" == *"after"* ]]
}

@test "integration: handles command failure gracefully" {
  skip_if_no_docker

  # `false` rather than a string "exit 1": the latter was rejected as a non-array
  # command, so this test passed on the error path instead of on a failing
  # container, which is the thing it is meant to check.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="false"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -ne 0 ]]
}
