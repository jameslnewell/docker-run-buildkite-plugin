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

  # A container that wrote through the mounted checkout leaves root's files in
  # it on a daemon without user-namespace remapping, and bats could not then
  # remove its own temp directory.
  if [[ -n "${mounted_job_dir:-}" ]]; then
    docker run --rm -v "${mounted_job_dir}:/job" busybox:latest chown -R "$(id -u):$(id -g)" /job
  fi
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

# --- copy-out ---
#
# copy-out writes into the job's working directory, so these run from an empty
# one rather than from the plugin's checkout. Unless a test is about the mounted
# checkout, the checkout is not mounted: what lands in the working directory was
# put there by the copy.
in_job_dir() {
  mkdir "${BATS_TEST_TMPDIR}/job"
  cd "${BATS_TEST_TMPDIR}/job"
  export BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT="false"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0="sh"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_1="-c"
}

@test "integration: copy-out resolves a relative from against a /workdir working directory" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /workdir/coverage to coverage"* ]]
  [[ "$(cat coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out resolves a relative from against a /workdir/backend working directory, and creates the parents of to" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir/backend"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/reports/coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /workdir/backend/coverage to backend/reports/coverage"* ]]
  [[ "$(cat backend/reports/coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out resolves a relative from against the image's own WORKDIR" {
  skip_if_no_docker
  in_job_dir

  # The one image the suite already depends on that sets a WORKDIR: /plugin,
  # where it expects a plugin to be mounted.
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="buildkite/plugin-tester"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /plugin/coverage to coverage"* ]]
  [[ "$(cat coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out resolves a relative from against / when the image has no WORKDIR" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /coverage to coverage"* ]]
  [[ "$(cat coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out uses an absolute from as is" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="echo report > /tmp/junit.xml"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/tmp/junit.xml:reports/junit.xml"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$(cat reports/junit.xml)" == "report" ]]
}

@test "integration: copy-out skips a from the container does not have" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="true"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Skipped /workdir/coverage: not found in the container"* ]]
  [[ -z "$(ls -A)" ]]
}

@test "integration: copy-out copies what a failed command wrote and exits with the command's status" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info && exit 3"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 3 ]]
  [[ "$(cat coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out replaces an existing to rather than copying into it" {
  skip_if_no_docker
  in_job_dir

  mkdir -p backend/coverage
  echo stale > backend/coverage/stale.txt
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$(ls -A backend/coverage)" == "lcov.info" ]]
  [[ "$(cat backend/coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out leaves to in place when the mounted checkout already put the output there" {
  skip_if_no_docker
  in_job_dir

  # The default mount-checkout puts the job's working directory at /workdir, so
  # the container's /workdir/coverage is the agent's coverage. On a daemon
  # without user-namespace remapping the container's files are root's, and
  # the agent could not remove them to put the copy in their place.
  unset BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT
  mounted_job_dir="$PWD"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Skipped /workdir/coverage: coverage already holds the same files"* ]]
  [[ "$(ls -A)" == "coverage" ]]
  [[ "$(ls -A coverage)" == "lcov.info" ]]
  [[ "$(cat coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out copies a mounted from to a to elsewhere in the checkout" {
  skip_if_no_docker
  in_job_dir

  unset BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT
  mounted_job_dir="$PWD"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:reports/coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /workdir/coverage to reports/coverage"* ]]
  [[ "$(cat reports/coverage/lcov.info)" == "covered" ]]
}

@test "integration: copy-out copies out of a volume mounted inside the mounted checkout" {
  skip_if_no_docker
  in_job_dir

  # /workdir/node_modules is the volume, not the checkout's directory of that
  # name, so the same path on both sides still has different contents.
  unset BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT
  mounted_job_dir="$PWD"
  export BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES_0="/workdir/node_modules"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="echo installed > node_modules/package.json"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="node_modules:node_modules"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$output" == *"Copied /workdir/node_modules to node_modules"* ]]
  [[ "$(cat node_modules/package.json)" == "installed" ]]
}

@test "integration: copy-out copies every entry" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir/backend"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage docs && echo covered > coverage/lcov.info && echo documented > docs/index.html"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:backend/docs"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 0 ]]
  [[ "$(cat backend/coverage/lcov.info)" == "covered" ]]
  [[ "$(cat backend/docs/index.html)" == "documented" ]]
}

@test "integration: copy-out fails the hook when the copy cannot be put in place" {
  skip_if_no_docker
  in_job_dir

  # A file where a parent of to has to be a directory.
  echo "not a directory" > backend
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir coverage && echo covered > coverage/lcov.info"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  run bash "$PLUGIN_PATH/hooks/command"

  [[ $status -eq 1 ]]
  [[ "$output" == *"Error: could not copy /workdir/coverage out of the container to backend/coverage"* ]]
  [[ "$(ls -A)" == "backend" ]]
}

@test "integration: copy-out copies in the post-command hook, from that hook's container" {
  skip_if_no_docker
  in_job_dir

  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR="/workdir"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_2="mkdir reports && echo report > reports/junit.xml"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="reports:reports"

  run bash "$PLUGIN_PATH/hooks/post-command"

  [[ $status -eq 0 ]]
  [[ "$(cat reports/junit.xml)" == "report" ]]
}
