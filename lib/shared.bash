#!/usr/bin/env bash

# Names the container (and the propagate-docker temp marker) for this run.
#
# A step can use the plugin more than once — as pre-command setup, as the
# command itself, as post-command teardown — and each of those runs creates its
# own container that lives until pre-exit. Keying the name on the job alone
# would make the second `docker create` fail with "container name already in
# use", so the pre/post hooks get the hook phase appended. The command hook
# keeps the bare job-id name it has always had.
plugin_run_name() {
  local hook="${BUILDKITE_PLUGIN_DOCKER_RUN_HOOK:-command}"
  if [[ "$hook" == "command" ]]; then
    printf '%s\n' "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}"
  else
    printf '%s\n' "docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}-${hook}"
  fi
}

# Reads a plugin array option into the global `result` array, returning non-zero
# when the option is unset so callers can branch on it. Named after (and behaving
# like) plugin_read_list_into_result in the official buildkite docker plugin.
#
# Items are appended to the array rather than printed and re-read line by line.
# A list item may legitimately contain newlines — `command: ["/bin/sh", "-ec", <script>]`
# passes an entire shell script as a single item — and any newline-delimited
# round-trip (`printf '%s\n'` piped into `mapfile -t`) turns such an item into one
# argv entry per line. That failure is silent and green: `sh -c` runs the first
# line as the script and binds the remaining lines to $0, $1, … so a step whose
# script is `cd <dir>` followed by real work only ever runs the `cd`, which
# succeeds.
plugin_read_list_into_result() {
  local prefix="$1"
  local i=0
  result=()
  while true; do
    local var="${prefix}_${i}"
    local value="${!var:-}"
    [[ -z "$value" ]] && break
    result+=("$value")
    # i=$((...)) rather than (( i++ )): the latter evaluates to 0 when i=0, which
    # set -e reads as a failure and would drop every item after index 0.
    i=$((i + 1))
  done
  # The agent exports the unindexed variable when the option was given as a
  # scalar rather than a YAML array.
  if [[ ${#result[@]} -eq 0 && -n "${!prefix:-}" ]]; then
    result+=("${!prefix}")
  fi
  [[ ${#result[@]} -gt 0 ]]
}

# Copies one path out of a stopped container to `to` in the job's working
# directory, replacing whatever is there. A `from` the container does not have
# is logged and skipped; any other failure returns non-zero.
plugin_copy_out() {
  local container="$1"
  local from="$2"
  local to="$3"
  local dest scratch
  local copy_status=0
  dest="$(pwd)/${to}"

  # `docker cp` cannot be asked whether a path exists, and how it words a
  # missing one varies between Docker versions. Asking for the path as a tar
  # stream answers it: a byte only arrives when the path is there. No byte
  # arrives when the container has gone or its filesystem cannot be read
  # either, so the path is only called missing if / does answer. If it does
  # not, the copy below fails with docker's own error.
  if [[ -z "$(docker cp "${container}:${from}" - 2>/dev/null | head -c 1)" \
    && -n "$(docker cp "${container}:/" - 2>/dev/null | head -c 1)" ]]; then
    echo "Skipped ${from}: not found in the container"
    return 0
  fi

  # The copy lands in a scratch directory and is then moved into place:
  # `docker cp` into a directory that already exists nests the copy inside it,
  # and removing `to` first would remove the source whenever a mount puts one
  # inside the other. The scratch directory is in the system temp dir rather
  # than the working directory, so that a `from` that contains the working
  # directory through a mount cannot include the scratch copy in itself.
  if ! scratch="$(mktemp -d "${TMPDIR:-/tmp}/docker-run-buildkite-plugin.XXXXXX")"; then
    echo "^^^ +++"
    echo "Error: could not create a directory to copy ${from} into"
    return 1
  fi

  set -x
  docker cp "${container}:${from}" "${scratch}/copy" || { copy_status=$?; } 2>/dev/null
  { set +x; } 2>/dev/null

  # A `to` that already holds the same files is left alone. That is the mounted
  # checkout: `from` and `to` are then one directory, which the container wrote
  # as root unless told otherwise, and an agent that is not root could not
  # remove it to put a copy of itself in its place.
  if [[ "$copy_status" -eq 0 ]] && diff -r "${scratch}/copy" "$dest" >/dev/null 2>&1; then
    rm -rf "$scratch"
    echo "Skipped ${from}: ${to} already holds the same files"
    return 0
  fi

  if [[ "$copy_status" -eq 0 ]]; then
    { mkdir -p "$(dirname "$dest")" && rm -rf "$dest" && mv "${scratch}/copy" "$dest"; } || copy_status=$?
  fi
  rm -rf "$scratch"

  if [[ "$copy_status" -ne 0 ]]; then
    echo "^^^ +++"
    echo "Error: could not copy ${from} out of the container to ${to}"
    return 1
  fi
  echo "Copied ${from} to ${to}"
}
