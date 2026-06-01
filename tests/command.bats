#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/../lib/shared.bash"

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

  export PLUGIN_DIR="${PLUGIN_DIR:-.}"
  export BUILDKITE_JOB_ID="test-job-id"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="ubuntu:24.04"
  # Disable mount-checkout by default so tests that don't cover that feature
  # can use simple exact-match stubs without the --workdir/-v args.
  export BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT="false"
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

@test "plugin_read_list with indexed array reads all items under set -e" {
  # Regression: (( i++ )) returns exit code 1 when i=0, which set -e in a
  # process substitution subshell would turn into an early exit, silently
  # dropping all items after index 0.
  export MY_VAR_0="first"
  export MY_VAR_1="second"
  export MY_VAR_2="third"
  mapfile -t result < <(set -e; plugin_read_list "MY_VAR")
  [[ "${#result[@]}" -eq 3 ]]
  [[ "${result[0]}" == "first" ]]
  [[ "${result[1]}" == "second" ]]
  [[ "${result[2]}" == "third" ]]
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
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Runs step command in shell" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 /bin/sh -e -c \"make test\" : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  unset BUILDKITE_COMMAND
}

@test "Errors when both step and plugin commands are specified" {
  export BUILDKITE_COMMAND="make test"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="echo plugin"

  stub docker \
    "pull ubuntu:24.04 : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
  assert_output --partial "Error:"
  unset BUILDKITE_COMMAND
}

@test "Plugin command as string errors" {
  unset BUILDKITE_COMMAND
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="node server.js"

  stub docker \
    "pull ubuntu:24.04 : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
  assert_output --partial "Error:"
}

@test "Plugin command array items passed as direct docker args" {
  unset BUILDKITE_COMMAND
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="node"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="server.js"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 node server.js : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Step command with shell false passed directly" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL="false"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 \"make test\" : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  unset BUILDKITE_COMMAND
}

@test "Custom shell array wraps step command" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_0="/bin/bash"
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_1="-e"
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_2="-c"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 /bin/bash -e -c \"make test\" : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  unset BUILDKITE_COMMAND
}

@test "Empty entrypoint clears image ENTRYPOINT and suppresses shell" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT=""
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true" \
    ":: true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run bash -c "${PLUGIN_DIR}/hooks/command 2>&1"

  assert_success
  # --entrypoint '' clears the image's ENTRYPOINT (matches official buildkite docker plugin)
  assert_output --partial "--entrypoint"
  # shell is suppressed — any entrypoint (even "") disables shell wrapping
  refute_output --partial "/bin/sh -e -c"
  unset BUILDKITE_COMMAND
}

@test "Entrypoint suppresses shell for step commands" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/sh"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty --entrypoint /bin/sh ubuntu:24.04 \"make test\" : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  unset BUILDKITE_COMMAND
}

@test "Shell array with entrypoint errors" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_0="/bin/bash"
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_1="-e"
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_2="-c"
  export BUILDKITE_COMMAND="make test"

  stub docker \
    "pull ubuntu:24.04 : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
  assert_output --partial "Error:"
}

@test "Shell as string errors" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_SHELL="/bin/bash -e -c"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND="echo hello"

  stub docker \
    "pull ubuntu:24.04 : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure
  assert_output --partial "Error:"
}

@test "Passes environment variables" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT_0="DATABASE_URL=postgres://localhost"
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT_1="NODE_ENV=test"

  run bash -c "source $PLUGIN_DIR/lib/shared.bash; plugin_read_list 'BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT'"

  [[ $status -eq 0 ]]
  [[ "$output" == *"DATABASE_URL=postgres://localhost"* ]]
  [[ "$output" == *"NODE_ENV=test"* ]]
}

@test "Passes volume mounts" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="/host:/container"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_1="/src:/app/src"

  run bash -c "source $PLUGIN_DIR/lib/shared.bash; plugin_read_list 'BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES'"

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
    "create --name docker-run-buildkite-plugin-test-job-id --tty --workdir /app ubuntu:24.04 : true" \
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
    "create --name docker-run-buildkite-plugin-test-job-id --tty --entrypoint /bin/bash ubuntu:24.04 : true" \
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

@test "Integration: plugin command and entrypoint passed directly" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workspace"
  export BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT="/bin/sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="node"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="server.js"
  unset BUILDKITE_COMMAND

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty --workdir /workspace --entrypoint /bin/sh ubuntu:24.04 node server.js : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "mount-checkout mounts checkout at /workdir by default" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT
  unset BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty --workdir /workdir -v $(pwd):/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "mount-checkout false does not mount checkout" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT="false"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "mount-checkout uses explicit workdir" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/app"
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty --workdir /app -v $(pwd):/app ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "propagate-buildkite-environment adds CI and BUILDKITE_* vars" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_ENVIRONMENT="true"
  export CI="true"
  export BUILDKITE="true"
  export BUILDKITE_BRANCH="main"

  # The full set of propagated vars depends on the environment; use :: true
  # and verify key vars appear in the xtrace output.
  stub docker \
    "pull ubuntu:24.04 : true" \
    ":: true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run bash -c "${PLUGIN_DIR}/hooks/command 2>&1"

  assert_success
  assert_output --partial "-e CI"
  assert_output --partial "-e BUILDKITE "
  assert_output --partial "-e BUILDKITE_BRANCH"
}

@test "propagate-docker mounts default socket when DOCKER_HOST is unset" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset DOCKER_HOST
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER="true"
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
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /var/run/docker.sock:/var/run/docker.sock -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "propagate-docker uses custom unix socket from DOCKER_HOST" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER="true"
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
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /run/user/1000/docker.sock:/var/run/docker.sock -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "propagate-docker passes DOCKER_HOST env var for TCP connections" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER="true"
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
    "create --name docker-run-buildkite-plugin-test-job-id --tty -e DOCKER_HOST=tcp://localhost:2375 -v /tmp/docker-run-test-tmpdir/config.json:/root/.docker/config.json ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$real_docker_config"
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "propagate-docker skips config mount when config.json does not exist" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset DOCKER_HOST
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER="true"
  export DOCKER_CONFIG="/nonexistent/docker-config"

  stub mktemp \
    "-d : echo /tmp/docker-run-test-tmpdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /var/run/docker.sock:/var/run/docker.sock ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -f "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
}

@test "Relative volume . is resolved to pwd" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0=".:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v $(pwd):/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Relative volume ./packages/foo is resolved to pwd" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="./packages/foo:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v $(pwd)/packages/foo:/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Absolute volume path is unchanged" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="/abs:/workdir"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /abs:/workdir ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "Container-only volume with no colon is unchanged" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="/workdir/node_modules"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /workdir/node_modules ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "propagate-ssh-agent mounts SSH auth socket and sets SSH_AUTH_SOCK" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_SSH_AGENT="true"
  export SSH_AUTH_SOCK="/run/ssh-agent.sock"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -v /run/ssh-agent.sock:/run/ssh-agent -e SSH_AUTH_SOCK=/run/ssh-agent ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "propagate-ssh-agent is skipped when SSH_AUTH_SOCK is unset" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  unset SSH_AUTH_SOCK
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_SSH_AGENT="true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "propagate-aws passes AWS credential and region env vars" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_AWS="true"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
}

@test "propagate-buildkite-agent mounts agent socket and passes access token" {
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND
  unset BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0
  export BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_AGENT="true"

  # Create a fake socket so the -S guard passes
  fake_socket_dir=$(mktemp -d)
  fake_socket="${fake_socket_dir}/buildkite-agent.sock"
  # Use a named pipe as a stand-in for a socket in tests
  mkfifo "$fake_socket" || true

  # Temporarily override the socket path by making the hook find it
  # We can't easily override the hardcoded path, so test against the actual path
  # This test verifies the env var is propagated; socket mounting depends on the path existing
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty -e BUILDKITE_AGENT_ACCESS_TOKEN ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  rm -rf "$fake_socket_dir"
}
