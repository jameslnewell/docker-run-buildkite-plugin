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
    "pull ubuntu:24.04 : echo 'Pulling ubuntu:24.04'" \
    "create --name docker-run-buildkite-plugin-test-job-id ubuntu:24.04 : echo 'Created container'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Container started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_output --partial "Pulling ubuntu:24.04"
  assert_output --partial "Created container"
  assert_output --partial "Container started"
}

@test "Passes command as string" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="echo hello"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id ubuntu:24.04 echo hello : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes command as array" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="bash"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="-c"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="echo hello"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id ubuntu:24.04 bash -c 'echo hello' : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes environment variables" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENV_0="FOO=bar"
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENV_1="BAZ=qux"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id -e FOO=bar -e BAZ=qux ubuntu:24.04 : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes volume mounts" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0="/host:/container"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_1="/another:/mount"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /host:/container -v /another:/mount ubuntu:24.04 : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes workdir option" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/app"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id --workdir /app ubuntu:24.04 : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Passes entrypoint option" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/bash"

  stub docker \
    "pull ubuntu:24.04 : echo 'Pulling'" \
    "create --name docker-run-buildkite-plugin-test-job-id --entrypoint /bin/bash ubuntu:24.04 : echo 'Created'" \
    "start --attach docker-run-buildkite-plugin-test-job-id : echo 'Started'"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Fails when docker pull fails" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="invalid/image:nonexistent"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND=""

  stub docker \
    "pull * : exit 1" \
    "rm -f * : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
}
