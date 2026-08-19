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
