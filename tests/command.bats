#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/../lib/shared.bash"

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

  export PLUGIN_DIR="${PLUGIN_DIR:-.}"
  export BUILDKITE_JOB_ID="test-job-id"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="ubuntu:24.04"
}

teardown() {
  unstub docker 2>/dev/null || true
}

@test "plugin_read_list with scalar value" {
  export MY_VAR="single-value"
  mapfile -t result < <(plugin_read_list "MY_VAR")
  [[ "${result[0]}" == "single-value" ]]
}

@test "plugin_read_list with indexed array" {
  export MY_VAR_0="first"
  export MY_VAR_1="second"
  export MY_VAR_2="third"
  result=$(plugin_read_list "MY_VAR")
  [[ "$result" == $'first\nsecond\nthird' ]]
}

@test "plugin_read_list with empty result" {
  unset MY_VAR
  unset MY_VAR_0
  mapfile -t result < <(plugin_read_list "MY_VAR")
  [[ "${#result[@]}" == "0" ]]
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
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="-c"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="echo success"

  run bash -c "source $PLUGIN_DIR/lib/shared.bash; plugin_read_list 'BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND'"

  [[ $status -eq 0 ]]
  [[ "$output" == *"sh"* ]]
  [[ "$output" == *"-c"* ]]
  [[ "$output" == *"echo success"* ]]
}

@test "Passes environment variables" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENV_0="DATABASE_URL=postgres://localhost"
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENV_1="NODE_ENV=test"

  run bash -c "source $PLUGIN_DIR/lib/shared.bash; plugin_read_list 'BUILDKITE_PLUGIN_DOCKER_RUN_ENV'"

  [[ $status -eq 0 ]]
  [[ "$output" == *"DATABASE_URL=postgres://localhost"* ]]
  [[ "$output" == *"NODE_ENV=test"* ]]
}

@test "Passes volume mounts" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0="/host:/container"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_1="/src:/app/src"

  run bash -c "source $PLUGIN_DIR/lib/shared.bash; plugin_read_list 'BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME'"

  [[ $status -eq 0 ]]
  [[ "$output" == *"/host:/container"* ]]
  [[ "$output" == *"/src:/app/src"* ]]
}

@test "script has valid bash syntax" {
  bash -n "$PLUGIN_DIR/hooks/command"
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
