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

# A `cp` to `-` is a probe: it asks for a path as a tar stream, and any output
# at all means the path is there. Each entry starts with a probe of `<from>/.`,
# which only a directory answers, and a directory is then copied as `<from>/.`
# so that its contents land in `to`. When that probe answers nothing, a probe of
# `<from>` itself tells a file from nothing at all, and one of / tells a missing
# path from a container that cannot be read. In the copy, $4 is the destination
# the hook handed to docker.

@test "copy-out resolves a relative from against the container's working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir/backend" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage/. backend/coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line -- "--- :docker: copying out"
  assert_line "docker cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/backend/coverage/. backend/coverage"
  assert_line "Copied /workdir/backend/coverage to backend/coverage"
  assert_equal "$(cat backend/coverage/lcov.info)" "covered"
}

@test "copy-out resolves a relative from against / when the container has no working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /coverage to coverage"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out uses an absolute from as is" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/tmp/coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/tmp/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/tmp/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /tmp/coverage to coverage"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out takes a leading ./ off from, and hands to to docker as it is written" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="./coverage:./backend/coverage/"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. ./backend/coverage/ : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to ./backend/coverage/"
  assert_equal "$(cat backend/coverage/lcov.info)" "covered"
}

@test "copy-out asks for a from written with a trailing slash as it does any other" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage/:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out copies a directory's contents into the working directory when to is ." {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="dist:."
  echo kept > .env

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/dist/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/dist/. . : echo built > \$4/app.js"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/dist to ."
  assert_equal "$(cat app.js)" "built"
  assert_equal "$(cat .env)" "kept"
}

@test "copy-out copies to a to outside the working directory" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:${BATS_TEST_TMPDIR}/elsewhere/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. ${BATS_TEST_TMPDIR}/elsewhere/coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/elsewhere/coverage/lcov.info")" "covered"
  assert_equal "$(ls -A)" ""
}

@test "copy-out copies a directory's contents to a to that is not there yet" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to coverage"
  assert_equal "$(ls -A coverage)" "lcov.info"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out copies a directory's contents into a to that is already there, and leaves what else it holds" {
  # Asked for as `coverage/.`, or docker would put it at coverage/coverage.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  mkdir coverage
  echo earlier > coverage/earlier.txt

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /workdir/coverage to coverage"
  assert_equal "$(cat coverage/lcov.info)" "covered"
  assert_equal "$(cat coverage/earlier.txt)" "earlier"
}

@test "copy-out copies a file to a path that is not there yet" {
  # A file has no contents to ask for, so it is copied under its own path.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/out/junit.xml:report.xml"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml/. - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml report.xml : echo results > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "docker cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml report.xml"
  assert_line "Copied /out/junit.xml to report.xml"
  assert_equal "$(cat report.xml)" "results"
}

@test "copy-out copies a file into a to that is a directory, and leaves what else it holds" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="/out/junit.xml:test-results"
  mkdir test-results
  echo earlier > test-results/earlier.xml

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml/. - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/out/junit.xml test-results : echo results > \$4/junit.xml"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Copied /out/junit.xml to test-results"
  assert_equal "$(cat test-results/junit.xml)" "results"
  assert_equal "$(cat test-results/earlier.xml)" "earlier"
}

@test "copy-out creates the directories above to" {
  # docker cp fails when the directory it is to write into does not exist.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:reports/backend/coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. reports/backend/coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat reports/backend/coverage/lcov.info)" "covered"
}

@test "copy-out copies every entry" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:backend/coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="junit.xml:backend/junit.xml"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. backend/coverage : mkdir \$4 && echo covered > \$4/lcov.info" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/junit.xml/. - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/junit.xml - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/junit.xml backend/junit.xml : echo results > \$4"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_equal "$(cat backend/coverage/lcov.info)" "covered"
  assert_equal "$(cat backend/junit.xml)" "results"
}

@test "copy-out copies what a failed command wrote and exits with the command's status" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out skips a from the container does not have" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs/. - : echo 'Error response from daemon: Could not find the file /workdir/docs/. in container docker-run-buildkite-plugin-test-job-id' >&2; exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs - : echo 'Error response from daemon: Could not find the file /workdir/docs in container docker-run-buildkite-plugin-test-job-id' >&2; exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/ - : echo tar"

  run "$PLUGIN_DIR/hooks/command"

  assert_success
  assert_line "Skipped /workdir/docs: not found in the container"
  [[ ! -e docs ]]
}

@test "copy-out does not call a from missing when the container cannot be read at all" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  # Neither the path nor / answers a probe, so the copy runs and its failure is
  # the hook's.
  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage - : exit 1" \
    "cp docker-run-buildkite-plugin-test-job-id:/ - : exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage coverage : echo 'Error response from daemon: No such container: docker-run-buildkite-plugin-test-job-id' >&2; exit 1"

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
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : echo 'write /builds/job/coverage/lcov.info: no space left on device' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "^^^ +++"
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
  assert_line "write /builds/job/coverage/lcov.info: no space left on device"
}

@test "copy-out keeps the command's exit status when it cannot create the directories above to" {
  # A failed copy like any other: it must not end the hook on the spot with
  # mkdir's status, and docker is not asked to copy into a directory that is
  # not there.
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:reports/coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"
  echo "not a directory" > reports

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs/. docs : mkdir \$4 && echo documented > \$4/index.html"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
  assert_line "Error: could not copy /workdir/coverage out of the container to reports/coverage"
  assert_equal "$(cat reports)" "not a directory"
  assert_equal "$(cat docs/index.html)" "documented"
}

@test "copy-out still copies the entries after one that failed" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_1="docs:docs"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : echo 'write /builds/job/coverage/lcov.info: no space left on device' >&2; exit 1" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/docs/. docs : mkdir \$4 && echo documented > \$4/index.html"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 1
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
  assert_line "Copied /workdir/docs to docs"
  assert_equal "$(cat docs/index.html)" "documented"
}

@test "copy-out keeps a failed command's status when the copy fails too" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id : exit 3" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id:/workdir/coverage/. coverage : echo 'write /builds/job/coverage/lcov.info: no space left on device' >&2; exit 1"

  run "$PLUGIN_DIR/hooks/command"

  assert_failure 3
  assert_line "Error: could not copy /workdir/coverage out of the container to coverage"
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

# --- the other hook phases copy in the hook that ran the container ---

@test "copy-out copies in the pre-command hook, from that hook's container" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="pre-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-pre-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-pre-command : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id-pre-command : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-pre-command:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-pre-command:/workdir/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/pre-command"

  assert_success
  assert_line "~~~ :docker: copying out"
  assert_equal "$(cat coverage/lcov.info)" "covered"
}

@test "copy-out copies in the post-command hook, from that hook's container" {
  export BUILDKITE_PLUGIN_DOCKER_RUN_HOOK="post-command"
  export BUILDKITE_PLUGIN_DOCKER_RUN_COPY_OUT_0="coverage:coverage"

  stub docker \
    "pull ubuntu:24.04 : true" \
    "create --name docker-run-buildkite-plugin-test-job-id-post-command --tty ubuntu:24.04 : true" \
    "start --attach docker-run-buildkite-plugin-test-job-id-post-command : true" \
    "${INSPECT_WORKDIR} docker-run-buildkite-plugin-test-job-id-post-command : echo /workdir" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-post-command:/workdir/coverage/. - : echo tar" \
    "cp --follow-link docker-run-buildkite-plugin-test-job-id-post-command:/workdir/coverage/. coverage : mkdir \$4 && echo covered > \$4/lcov.info"

  run "$PLUGIN_DIR/hooks/post-command"

  assert_success
  assert_line "~~~ :docker: copying out"
  assert_equal "$(cat coverage/lcov.info)" "covered"
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
