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

@test "hooks/post-command no-ops when hook is unset (defaults to command)" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_output ""
}

@test "hooks/post-command no-ops when hook is command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="command"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_output ""
}

@test "hooks/post-command no-ops when hook is pre-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_output ""
}

@test "hooks/command no-ops when hook is post-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_output ""
}

@test "hooks/pre-command no-ops when hook is post-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  assert_output ""
}

# --- post-command runs docker ---

@test "hooks/post-command runs docker when hook is post-command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="run"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="reports:upload"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 npm run reports:upload : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
}

@test "hooks/post-command uses collapsed log groups" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 true : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_line "~~~ :docker: running"
  refute_line --partial "+++ :docker: running"
}

# --- post-command ignores the step's command ---

@test "hooks/post-command runs the plugin command when the step also has a command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_COMMAND="make test"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="npm"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="run"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="reports:upload"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 npm run reports:upload : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  refute_output --partial "Error:"
  unset BUILDKITE_COMMAND
}

@test "hooks/post-command leaves the step's command to the command hook" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_COMMAND="make test"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0

  # No plugin command and no step command of ours to run — the image's own CMD runs.
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  unset BUILDKITE_COMMAND
}

# --- container naming keeps bracketing runs apart ---

@test "each hook phase gets its own container name" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_HOOK
  [[ "$(plugin_run_name)" == "docker-run-buildkite-plugin-test-job-id" ]]

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="command"
  [[ "$(plugin_run_name)" == "docker-run-buildkite-plugin-test-job-id" ]]

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  [[ "$(plugin_run_name)" == "docker-run-buildkite-plugin-test-job-id-pre-command" ]]

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  [[ "$(plugin_run_name)" == "docker-run-buildkite-plugin-test-job-id-post-command" ]]
}

@test "hooks/post-command has valid bash syntax" {
  bash -n "$PLUGIN_DIR/hooks/post-command"
}
