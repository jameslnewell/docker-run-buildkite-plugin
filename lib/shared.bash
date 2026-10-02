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

# Prints the agent's path for a container path that a bind mount puts on the
# agent, and an empty line for any other path. `mounts` is the container's
# mounts, one "<type>\t<destination>\t<source>" per line.
#
# The deepest mount containing the path decides. A volume mounted inside the
# checkout (`/workdir/node_modules`) hides the checkout's own directory of that
# name, so a path under it is not the agent's.
plugin_bind_mounted_path() {
  local path="$1"
  local mounts="$2"
  local type destination source
  local deepest=""
  local mounted=""
  while IFS=$'\t' read -r type destination source; do
    [[ -n "$type" ]] || continue
    destination="${destination%/}"
    [[ "$path" == "$destination" || "$path" == "${destination}/"* ]] || continue
    [[ ${#destination} -ge ${#deepest} ]] || continue
    deepest="$destination"
    mounted=""
    [[ "$type" != "bind" ]] || mounted="${source%/}${path#"$destination"}"
  done <<< "$mounts"
  printf '%s\n' "$mounted"
}

# Copies one path out of a stopped container to `to` in the job's working
# directory, replacing whatever is there. A `from` the container does not have
# is logged and skipped; any other failure returns non-zero.
plugin_copy_out() {
  local container="$1"
  local from="$2"
  local to="$3"
  local mounts="$4"
  local dest mounted scratch error
  dest="$(pwd)/${to}"

  # With the checkout mounted over the container's working directory, `from` and
  # `to` can be one directory, and the output is already where it was asked for.
  # Replacing it with a copy of itself would only fail on a daemon without
  # user-namespace remapping, where the container's files are root's and the
  # agent cannot remove them.
  mounted="$(plugin_bind_mounted_path "$from" "$mounts")"
  if [[ -n "$mounted" && "$mounted" -ef "$dest" ]]; then
    echo "Skipped ${from}: already at ${to} through a mount"
    return 0
  fi

  # The copy lands in a scratch directory and is then moved into place:
  # `docker cp` into a directory that already exists nests the copy inside it,
  # and removing `to` first would remove the source whenever a mount puts one
  # inside the other. The scratch directory is in the system temp dir rather
  # than the working directory, so that a `from` that contains the working
  # directory through a mount cannot include the scratch copy in itself.
  if ! scratch="$(mktemp -d "${TMPDIR:-/tmp}/docker-run-buildkite-plugin.XXXXXX")"; then
    echo "+++ Error: Could not create a directory to copy ${from} into."
    return 1
  fi

  if ! error="$(docker cp "${container}:${from}" "${scratch}/copy" 2>&1)"; then
    rm -rf "$scratch"
    # The daemon's wording, then the Docker 20.10 CLI's.
    if [[ "$error" == *"Could not find the file"* || "$error" == *"No such container:path"* ]]; then
      echo "Skipped ${from}: not found in the container"
      return 0
    fi
    echo "+++ Error: Could not copy ${from} out of the container."
    printf '%s\n' "$error"
    return 1
  fi

  if ! { mkdir -p "$(dirname "$dest")" && rm -rf "$dest" && mv "${scratch}/copy" "$dest"; }; then
    rm -rf "$scratch"
    echo "+++ Error: Could not move the copy of ${from} to ${to}."
    return 1
  fi

  rm -rf "$scratch"
  echo "Copied ${from} to ${to}"
}
