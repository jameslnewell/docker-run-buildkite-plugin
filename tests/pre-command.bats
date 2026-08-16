#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/../lib/shared.bash"

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

  export PLUGIN_DIR="${PLUGIN_DIR:-.}"
  export BUILDKITE_JOB_ID="test-job-id"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="ubuntu:24.04"
  export BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT="false"
}

teardown() {
  unstub docker 2>/dev/null || true
}

# --- hook routing ---

@test "hooks/command no-ops when hook is pre-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_output ""
}

@test "hooks/pre-command no-ops when hook is unset (defaults to command)" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  assert_output ""
}

@test "hooks/pre-command no-ops when hook is command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="command"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  assert_output ""
}

# --- pre-command runs docker ---

@test "hooks/pre-command runs docker when hook is pre-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="run"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="secrets:pull"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty ubuntu:24.04 npm run secrets:pull : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
}

@test "hooks/pre-command respects volumes and propagate-aws" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="run"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="secrets:pull"
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_AWS="true"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="/host/file.yml:/workdir/file.yml:ro"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_1="/host/env.d/:/workdir/env.d/"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty -v /host/file.yml:/workdir/file.yml:ro -v /host/env.d/:/workdir/env.d/ -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN ubuntu:24.04 npm run secrets:pull : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
}

# --- pre-command ignores the step's command ---

@test "hooks/pre-command runs the plugin command when the step also has a command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_COMMAND="make test"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="run"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="secrets:pull"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty ubuntu:24.04 npm run secrets:pull : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  refute_output --partial "Error:"
  unset BUILDKITE_COMMAND
}

@test "hooks/pre-command leaves the step's command to the command hook" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_COMMAND="make test"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0

  # No plugin command and no step command of ours to run — the image's own CMD runs.
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  unset BUILDKITE_COMMAND
}

@test "hooks/command still errors when both step and plugin commands are specified" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="command"
  export BUILDKITE_COMMAND="make test"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="test"

  stub docker \
    "pull ubuntu:24.04 : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
  assert_output --partial "Error:"
  unset BUILDKITE_COMMAND
}

@test "hooks/pre-command has valid bash syntax" {
  bash -n "$PLUGIN_DIR/hooks/pre-command"
}
