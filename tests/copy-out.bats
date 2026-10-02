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

  # What the hook asks docker about the stopped container, as a stub pattern.
  # Each test appends the container name and what docker answers.
  INSPECT_WORKDIR="container inspect --format {{.Config.WorkingDir}}"
}

# Not `|| true`, unlike tests/command.bats: the plan is the assertion here. A
# copy that never ran, or ran before the container exited, fails the unstub.
teardown() {
  unstub docker
}

# Each entry is two `cp` calls: a probe that asks for the path as a tar stream
# (`-`), where any output at all means the path exists, and then the copy, where
# $4 is the destination the hook handed to docker. A probe that answers nothing
# is followed by the same probe of /, which tells a missing path from a
# container that cannot be read at all.

@test "copy-out resolves a relative from against the container's working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir/backend" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage * : echo covered > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/coverage * : echo covered > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/tmp/report.xml - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/tmp/report.xml * : echo report > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat report.xml)" "report"
}

@test "copy-out takes a leading ./ on either side and a trailing slash on to" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="./coverage:./backend/coverage/"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to backend/coverage"
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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$4" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo documented > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat coverage/lcov.info)" "covered"
  assert_equal "$(ls -A coverage)" "lcov.info"
}

@test "copy-out stages the copy inside the job's working directory" {
  # On the destination's filesystem, so that the move into place is a rename.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo \$4 > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_regex "$(cat coverage)" "^${PWD}/\.docker-run-copy-out\.[A-Za-z0-9]+/copy$"
}

@test "copy-out leaves nothing of its own in the job's working directory" {
  # The copy is staged in a scratch directory inside the job's working directory,
  # which has to be gone whether the entry was copied, skipped or failed.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_2="dist:dist"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$4" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/ - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/dist - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/dist * : mkdir \$4 && exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_equal "$(ls -A)" "coverage"
}

@test "copy-out copies what a failed command wrote and exits with the command's status" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo covered > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : echo 'Error response from daemon: Could not find the file /workdir/docs in container docker-run-buildkite-plugin-test-job-id' >&2; exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/ - : echo tar"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/docs: not found in the container"
  [[ ! -e docs ]]
}

@test "copy-out does not call a from missing when the container cannot be read at all" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  # Neither the path nor / answers the probe, so the copy runs and its failure
  # is the hook's.
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/ - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: No such container: docker-run-buildkite-plugin-test-job-id' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  refute_output --partial "Skipped"
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
}

@test "copy-out fails the hook when the copy fails for any other reason" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "^^^ +++"
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
  assert_line "Error response from daemon: lstat /workdir/coverage: not a directory"
  [[ ! -e coverage ]]
}

@test "copy-out leaves to as it was when the copy fails partway" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo earlier > coverage/lcov.info

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$4 && echo partial > \$4/lcov.info; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_equal "$(cat coverage/lcov.info)" "earlier"
}

@test "copy-out keeps the command's exit status when it has nowhere to stage a copy" {
  # A working directory that cannot be written to is a failed copy like any
  # other: it must not end the hook on the spot with mktemp's status.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"
  mkdir "${BATS_TEST_TMPDIR}/shims"
  printf '#!/bin/sh\necho "mktemp: failed to create directory" >&2\nexit 1\n' > "${BATS_TEST_TMPDIR}/shims/mktemp"
  chmod +x "${BATS_TEST_TMPDIR}/shims/mktemp"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : echo tar"

  run env PATH="${BATS_TEST_TMPDIR}/shims:${PATH}" "$PLUGIN_DIR/hooks/command"

  assert_failure 3
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
  assert_line "Error: could not copy /workdir/docs out of the container to docs"
}

@test "copy-out still copies the entries after one that failed" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs * : echo documented > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : echo 'Error response from daemon: lstat /workdir/coverage: not a directory' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
}

@test "copy-out fails the hook when there is no container to copy out of" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "^^^ +++"
  assert_line "Error: there is no container to copy out of"
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

# --- a to that already holds what was copied ---

@test "copy-out leaves a to that already holds the same files in place" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo covered > coverage/lcov.info
  before="$(ls -di coverage)"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/coverage: coverage already holds the same files"
  # The same directory as before, not an identical one moved into its place.
  assert_equal "$(ls -di coverage)" "$before"
  assert_equal "$(ls -A)" "coverage"
}

@test "copy-out replaces a to that holds the same file names with different contents" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo stale > coverage/lcov.info

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to coverage"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out replaces a file at to with a directory that holds a file of the same name and content" {
  # `diff` between a directory and a file compares the file with the directory's
  # entry of that name, and would call these two the same.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:lcov.info"
  echo covered > lcov.info

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage * : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to lcov.info"
  assert_equal "$(cat lcov.info/lcov.info)" "covered"
}

@test "copy-out replaces a directory at to with a file, whatever the directory holds" {
  # The copy is staged as a file named `copy`, which is the entry `diff` would
  # compare it with inside the directory.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/out/report.txt:reports"
  mkdir reports
  echo report > reports/copy

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/report.txt - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/report.txt * : echo report > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /out/report.txt to reports"
  [[ -f reports ]]
  assert_equal "$(cat reports)" "report"
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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-pre-command:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-pre-command:/workdir/coverage * : echo covered > \$4"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-post-command:/workdir/coverage - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-post-command:/workdir/coverage * : echo covered > \$4"

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

@test "copy-out to a path with a . component fails before anything is pulled, and says so" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:backend/./dist"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: The <to> of a copy-out entry must be a path inside the job's working directory."
  assert_line --partial 'have a "." or ".." component'
}

# `./` and `/` are the working directory and the root with nothing left once the
# prefix and the trailing slashes are stripped. Accepted, either would have the
# copy remove the job's working directory.
@test "copy-out to ./ fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:./"
  stub docker

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line --partial "+++ Error: The <to> of a copy-out entry must be a path inside the job's working directory."
}

@test "copy-out to / fails before anything is pulled" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:/"
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
