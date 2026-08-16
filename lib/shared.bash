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

plugin_read_list() {
  local prefix="$1"
  local i=0
  local found=0
  while true; do
    local var="${prefix}_${i}"
    local value="${!var:-}"
    [[ -z "$value" ]] && break
    printf '%s\n' "$value"
    found=1
    (( i++ )) || true  # post-increment evaluates to old value; || true prevents set -e exit when i=0
  done
  if [[ "$found" -eq 0 ]]; then
    local single="${!prefix:-}"
    [[ -n "$single" ]] && printf '%s\n' "$single"
  fi
  return 0
}
