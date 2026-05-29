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
  unstub mktemp 2>/dev/null || true
  unstub cp 2>/dev/null || true
  unstub chmod 2>/dev/null || true
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

@test "docker_from_docker mounts default socket when DOCKER_HOST is unset" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset DOCKER_HOST
  export BUILDKITE_PLUGIN_DOCKER_RUN_DOCKER_FROM_DOCKER="true"
  # Create a real config file before the mktemp stub so the -f guard passes
  real_docker_config=$(mktemp -d)
  echo '{}' > "${real_docker_config}/config.json"
  export DOCKER_CONFIG="$real_docker_config"

  stub mktemp \
    "-d : echo /tmp/docker-run-test-tmpdir"

  stub cp \
    "${real_docker_config}/config.json /tmp/docker-run-test-tmpdir/config.json : true"

  stub chmod \
    "0644 /tmp/docker-run-test-tmpdir/config.json : true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /var/run/docker.sock:/var/run/docker.sock -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "docker_from_docker uses custom unix socket from DOCKER_HOST" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_DOCKER_FROM_DOCKER="true"
  export DOCKER_HOST="unix:///run/user/1000/docker.sock"
  real_docker_config=$(mktemp -d)
  echo '{}' > "${real_docker_config}/config.json"
  export DOCKER_CONFIG="$real_docker_config"

  stub mktemp \
    "-d : echo /tmp/docker-run-test-tmpdir"

  stub cp \
    "${real_docker_config}/config.json /tmp/docker-run-test-tmpdir/config.json : true"

  stub chmod \
    "0644 /tmp/docker-run-test-tmpdir/config.json : true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /run/user/1000/docker.sock:/var/run/docker.sock -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "docker_from_docker passes DOCKER_HOST env var for TCP connections" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_DOCKER_FROM_DOCKER="true"
  export DOCKER_HOST="tcp://localhost:2375"
  real_docker_config=$(mktemp -d)
  echo '{}' > "${real_docker_config}/config.json"
  export DOCKER_CONFIG="$real_docker_config"

  stub mktemp \
    "-d : echo /tmp/docker-run-test-tmpdir"

  stub cp \
    "${real_docker_config}/config.json /tmp/docker-run-test-tmpdir/config.json : true"

  stub chmod \
    "0644 /tmp/docker-run-test-tmpdir/config.json : true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -e DOCKER_HOST=tcp://localhost:2375 -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "docker_from_docker skips config mount when config.json does not exist" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset DOCKER_HOST
  export BUILDKITE_PLUGIN_DOCKER_RUN_DOCKER_FROM_DOCKER="true"
  export DOCKER_CONFIG="/nonexistent/docker-config"

  stub mktemp \
    "-d : echo /tmp/docker-run-test-tmpdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /var/run/docker.sock:/var/run/docker.sock ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "Relative volume . is resolved to pwd" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0=".:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v $(pwd):/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Relative volume ./packages/foo is resolved to pwd" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0="./packages/foo:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v $(pwd)/packages/foo:/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Absolute volume path is unchanged" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0="/abs:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /abs:/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Container-only volume with no colon is unchanged" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUME_0="/workdir/node_modules"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id -v /workdir/node_modules ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}
