#!/usr/bin/env bats

setup() {
  load "${BATS_LIB_PATH}/bats-support/load.bash"
  load "${BATS_LIB_PATH}/bats-assert/load.bash"
  load "${BATS_LIB_PATH}/bats-mock/stub.bash"

  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PLUGIN_DIR
  export BUILDKITE_JOB_ID="test-job-id"
  export BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE="ubuntu:24.04"
  export BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT="false"

  # copy-out writes into the job's working directory. The suite's own is the
  # plugin checkout, which buildkite/plugin-tester mounts read-only.
  mkdir "${BATS_TEST_TMPDIR}/job"
  cd "${BATS_TEST_TMPDIR}/job"

  # The two things the hook asks docker about the stopped container, as stub
  # patterns. Each test appends the container name and what docker answers.
  INSPECT_WORKDIR="container inspect --format {{.Config.WorkingDir}}"
  INSPECT_MOUNTS="container inspect --format '{{range .Mounts}}{{.Type}}{{\"\\t\"}}{{.Destination}}{{\"\\t\"}}{{.Source}}{{\"\\n\"}}{{end}}'"
}

# Not `|| true`, unlike tests/command.bats: the plan is the assertion here. A
# copy that never ran, or ran before the container exited, fails the unstub.
teardown() {
  unstub docker
}

# In every `cp` stub below, $3 is the destination the hook handed to docker.

@test "copy-out resolves a relative from against the container's working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir/backend" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line -- "--- :docker: copying out"
  assert_line "Copied /workdir/backend/coverage to backend/coverage"
  assert_equal "$(cat backend/coverage)" "covered"
}

@test "copy-out resolves a relative from against / when the container has no working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat coverage)" "covered"
}

@test "copy-out uses an absolute from as is" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/tmp/report.xml:report.xml"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/tmp/report.xml * : echo report > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat report.xml)" "report"
}

@test "copy-out resolves a to beginning with ./ against the job's working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:./backend/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat backend/coverage)" "covered"
}

@test "copy-out copies every entry" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:backend/docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$3" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo documented > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat backend/coverage)" "covered"
  assert_equal "$(cat backend/docs)" "documented"
}

@test "copy-out replaces an existing to rather than copying into it" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo stale > coverage/stale.txt

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$3 && echo covered > \$3/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat coverage/lcov.info)" "covered"
  assert_equal "$(ls -A coverage)" "lcov.info"
}

@test "copy-out leaves nothing but the copy in the job's working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$3" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo 'Error response from daemon: Could not find the file /workdir/docs in container docker-run-buildkite-plugin-test-job-id' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(ls -A)" "coverage"
}

@test "copy-out copies what a failed command wrote and exits with the command's status" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
  assert_equal "$(cat coverage)" "covered"
}

@test "copy-out skips a from the container does not have" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo 'Error response from daemon: Could not find the file /workdir/docs in container docker-run-buildkite-plugin-test-job-id' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/docs: not found in the container"
  [[ ! -e docs ]]
}

@test "copy-out skips a missing from as Docker 20.10 reports it" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo 'Error: No such container:path: docker-run-buildkite-plugin-test-job-id:/workdir/docs' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/docs: not found in the container"
  [[ ! -e docs ]]
}

@test "copy-out fails the hook when the copy fails for any other reason" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "+++ Error: Could not copy /workdir/coverage out of the container."
  assert_line "Error response from daemon: lstat /workdir/coverage: not a directory"
  [[ ! -e coverage ]]
}

@test "copy-out still copies the entries after one that failed" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo documented > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_equal "$(cat docs)" "documented"
}

@test "copy-out keeps a failed command's status when the copy fails too" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : true" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
}

@test "copy-out fails the hook when the container's working directory cannot be read" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "+++ Error: Could not read the container's working directory and mounts."
}

@test "copy-out unset runs nothing after the container exits" {
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  refute_output --partial "copying out"
}

# --- a mount that already puts from at to ---

@test "copy-out leaves the output where it is when a bind mount already puts it at to" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo covered > coverage/lcov.info

  # No cp in the plan: the checkout is mounted at /workdir, so the container's
  # /workdir/coverage is the directory above.
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : printf 'bind\\t/workdir\\t%s\\n' ${PWD}"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/coverage: already at coverage through a mount"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out copies a bind-mounted from that is not already at to" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"
  mkdir coverage
  echo covered > coverage/lcov.info

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : printf 'bind\\t/workdir\\t%s\\n' ${PWD}" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo copied > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat backend/coverage)" "copied"
}

@test "copy-out copies out of a volume mounted inside the mounted checkout" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="node_modules:node_modules"
  # The mount point docker leaves in the checkout. The container's node_modules
  # is the volume, not this directory.
  mkdir node_modules

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id : printf 'volume\\t/workdir/node_modules\\t/var/lib/docker/volumes/abc/_data\\nbind\\t/workdir\\t%s\\n' ${PWD}" \
    "cp docker-run-buildkite-plugin-test-job-id:/workdir/node_modules * : echo installed > \$3"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat node_modules)" "installed"
}

# --- the other hook phases copy in the hook that ran the container ---

@test "copy-out copies in the pre-command hook, from that hook's container" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id-pre-command : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id-pre-command : true" \
    "cp docker-run-buildkite-plugin-test-job-id-pre-command:/workdir/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  assert_line "~~~ :docker: copying out"
  assert_equal "$(cat coverage)" "covered"
}

@test "copy-out copies in the post-command hook, from that hook's container" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id-post-command : echo /workdir" \
    "${INSPECT_MOUNTS} docker-run-buildkite-plugin-test-job-id-post-command : true" \
    "cp docker-run-buildkite-plugin-test-job-id-post-command:/workdir/coverage * : echo covered > \$3"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_line "~~~ :docker: copying out"
  assert_equal "$(cat coverage)" "covered"
}

# --- malformed entries fail before the container is created ---
#
# Each stubs docker with an empty plan, so any docker call at all fails the test.

@test "copy-out entry with no colon fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: Each copy-out entry must be \"<from>:<to>\""
  assert_line --partial "Got \"coverage\"."
}

@test "copy-out entry with two colons fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="test:coverage:backend/coverage"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: Each copy-out entry must be \"<from>:<to>\""
}

@test "copy-out entry with an empty from fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0=":coverage"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: Each copy-out entry must be \"<from>:<to>\""
}

@test "copy-out entry with an empty to fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: Each copy-out entry must be \"<from>:<to>\""
}

@test "copy-out fails on a malformed entry after a well-formed one" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "Got \"docs\"."
}

# `to` is removed to make way for the copy, so these would otherwise delete the
# checkout, or something outside it.

@test "copy-out to the working directory itself fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:."
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: The <to> of a copy-out entry must be a path inside the job's working directory."
}

@test "copy-out to an absolute path fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:/var/lib/dist"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: The <to> of a copy-out entry must be a path inside the job's working directory."
}

@test "copy-out to a path that climbs out of the working directory fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:backend/../../dist"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: The <to> of a copy-out entry must be a path inside the job's working directory."
}
