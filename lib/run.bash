source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.bash"

IMAGE="${BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE}"
CONTAINER_NAME="docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}"

# Buildkite treats lines beginning with ---, +++ or ~~~ as log-group headers.
# The agent *sources* this hook (which sources this file), so `set -x` runs a
# few shell-nesting levels deep, and bash replicates PS4's first character once
# per level — the default '+ ' becomes '+++ ', which Buildkite then parses as a
# group header (each traced command becomes its own section, leaving our
# intended groups empty). An empty PS4 emits no prefix at all (bash does not
# fall back to a default), so the traced command itself starts the line — and
# every command we trace begins with `docker`, never a marker.
PS4=''

# Use collapsed log groups (~~~) in pre-command mode so setup output stays
# out of the way of the main command's log groups.
if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_HOOK:-command}" == "pre-command" ]]; then
  _GROUP="~~~"
  _RUN_GROUP="~~~"
else
  _GROUP="---"
  _RUN_GROUP="+++"
fi

echo "${_GROUP} :docker: pulling"
set -x
docker pull "$IMAGE"
{ set +x; } 2>/dev/null

echo "${_GROUP} :docker: creating"

CREATE_ARGS=(--tty)

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT:-true}" != "false" ]]; then
  effective_workdir="${BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR:-/workdir}"
  CREATE_ARGS+=(--workdir "$effective_workdir")
  CREATE_ARGS+=(-v "$(pwd):${effective_workdir}")
else
  workdir="${BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR:-}"
  [[ -n "$workdir" ]] && CREATE_ARGS+=(--workdir "$workdir")
fi

entrypoint=""
if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT+set}" == "set" ]]; then
  entrypoint="${BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT}"
  CREATE_ARGS+=(--entrypoint "$entrypoint")
fi

mapfile -t ENVS < <(plugin_read_list "BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT")
for e in "${ENVS[@]}"; do
  CREATE_ARGS+=(-e "$e")
done

mapfile -t VOLUMES < <(plugin_read_list "BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES")
for v in "${VOLUMES[@]}"; do
  if [[ "$v" == *:* ]]; then
    host="${v%%:*}"
    rest="${v#*:}"
    if [[ "$host" == .* ]]; then
      host="$(pwd)${host#.}"
    fi
    v="${host}:${rest}"
  fi
  CREATE_ARGS+=(-v "$v")
done

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_SSH_AGENT:-false}" == "true" ]]; then
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    CREATE_ARGS+=(-v "${SSH_AUTH_SOCK}:/run/ssh-agent")
    CREATE_ARGS+=(-e "SSH_AUTH_SOCK=/run/ssh-agent")
  fi
fi

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_AWS:-false}" == "true" ]]; then
  CREATE_ARGS+=(-e "AWS_REGION")
  CREATE_ARGS+=(-e "AWS_DEFAULT_REGION")
  CREATE_ARGS+=(-e "AWS_ACCESS_KEY_ID")
  CREATE_ARGS+=(-e "AWS_SECRET_ACCESS_KEY")
  CREATE_ARGS+=(-e "AWS_SESSION_TOKEN")
fi

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_ENVIRONMENT:-false}" == "true" ]]; then
  while IFS='=' read -r key _; do
    if [[ "$key" == "CI" || "$key" == "BUILDKITE" || "$key" == BUILDKITE_* ]]; then
      CREATE_ARGS+=(-e "$key")
    fi
  done < <(env)
fi

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_AGENT:-false}" == "true" ]]; then
  BUILDKITE_AGENT_SOCKET="/run/buildkite-agent/buildkite-agent.sock"
  if [[ -S "${BUILDKITE_AGENT_SOCKET}" ]]; then
    CREATE_ARGS+=(-v "${BUILDKITE_AGENT_SOCKET}:${BUILDKITE_AGENT_SOCKET}")
  fi
  CREATE_ARGS+=(-e "BUILDKITE_AGENT_ACCESS_TOKEN")
fi

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER:-false}" == "true" ]]; then
  DOCKER_RUN_TMPDIR="$(mktemp -d)"
  DOCKER_HOST_VALUE="${DOCKER_HOST:-unix:///var/run/docker.sock}"
  if [[ "$DOCKER_HOST_VALUE" == unix://* ]]; then
    DOCKER_SOCKET="${DOCKER_HOST_VALUE#unix://}"
    CREATE_ARGS+=(-v "${DOCKER_SOCKET}:/var/run/docker.sock")
  else
    # TCP daemon — no socket to mount; pass DOCKER_HOST so the container's docker client connects directly
    CREATE_ARGS+=(-e "DOCKER_HOST=${DOCKER_HOST_VALUE}")
  fi
  # Copy rather than directly mounting: the original file is owned by the agent user (mode 0600)
  # and may not be readable inside the container without --userns host. A 0644 copy avoids that.
  DOCKER_CONFIG_DIR="${DOCKER_CONFIG:-${HOME}/.docker}"
  if [[ -f "${DOCKER_CONFIG_DIR}/config.json" ]]; then
    cp "${DOCKER_CONFIG_DIR}/config.json" "${DOCKER_RUN_TMPDIR}/config.json"
    chmod 0644 "${DOCKER_RUN_TMPDIR}/config.json"
    CREATE_ARGS+=(-v "${DOCKER_RUN_TMPDIR}/config.json:/root/.docker/config.json")
  fi
  echo "$DOCKER_RUN_TMPDIR" > "/tmp/docker-run-buildkite-plugin-${BUILDKITE_JOB_ID}.tmpdir"
fi

if [[ -n "${BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND:-}" && -z "${BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0:-}" ]]; then
  echo "+++ Error: The command option must be an array, not a string. Use command: ['arg1', 'arg2']."
  exit 1
fi
mapfile -t CMD_ITEMS < <(plugin_read_list "BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND")
has_step_commands=false
[[ -n "${BUILDKITE_COMMAND:-}" ]] && has_step_commands=true
has_plugin_commands=false
[[ ${#CMD_ITEMS[@]} -gt 0 ]] && has_plugin_commands=true

if [[ "$has_step_commands" == "true" && "$has_plugin_commands" == "true" ]]; then
  echo "+++ Error: Cannot specify both step commands and plugin commands. Move commands to the step or to the plugin 'command' option, not both."
  exit 1
fi

# Determine shell (only applies to step commands)
SHELL_ARGS=()
shell_enabled=true
shell_explicitly_set=false
if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_SHELL:-}" =~ ^(false|off|0)$ ]]; then
  shell_enabled=false
elif [[ -n "${BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_0:-}" ]]; then
  mapfile -t SHELL_ARGS < <(plugin_read_list "BUILDKITE_PLUGIN_DOCKER_RUN_SHELL")
  shell_explicitly_set=true
elif [[ -n "${BUILDKITE_PLUGIN_DOCKER_RUN_SHELL:-}" ]]; then
  echo "+++ Error: The shell option must be an array or false, not a string."
  exit 1
else
  SHELL_ARGS=("/bin/sh" "-e" "-c")
fi

# Any entrypoint (even "") suppresses shell wrapping — matches official buildkite docker plugin.
[[ "${BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT+set}" == "set" ]] && shell_enabled=false

# Error if shell was explicitly set as an array but entrypoint suppresses it.
if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT+set}" == "set" && "$shell_explicitly_set" == "true" ]]; then
  echo "+++ Error: The shell option has no effect when entrypoint is set — entrypoint suppresses shell wrapping."
  exit 1
fi

declare -a DOCKER_ARGS=(create --name "$CONTAINER_NAME")
DOCKER_ARGS+=("${CREATE_ARGS[@]}")
DOCKER_ARGS+=("$IMAGE")

if [[ "$has_step_commands" == "true" ]]; then
  if [[ "$shell_enabled" == "true" ]]; then
    DOCKER_ARGS+=("${SHELL_ARGS[@]}" "$BUILDKITE_COMMAND")
  else
    DOCKER_ARGS+=("$BUILDKITE_COMMAND")
  fi
elif [[ "$has_plugin_commands" == "true" ]]; then
  # Plugin commands are passed directly as docker CMD args — no shell wrapper
  DOCKER_ARGS+=("${CMD_ITEMS[@]}")
fi

set -x
docker "${DOCKER_ARGS[@]}"
{ set +x; } 2>/dev/null

echo "${_RUN_GROUP} :docker: running"
docker start --attach "$CONTAINER_NAME"
