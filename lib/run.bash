source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.bash"

IMAGE="${BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE}"
HOOK="${BUILDKITE_PLUGIN_DOCKER_RUN_HOOK:-command}"
CONTAINER_NAME="$(plugin_run_name)"

# Buildkite treats lines beginning with ---, +++ or ~~~ as log-group headers.
# The agent *sources* this hook (which sources this file), so `set -x` runs a
# few shell-nesting levels deep, and bash replicates PS4's first character once
# per level — the default '+ ' becomes '+++ ', which Buildkite then parses as a
# group header (each traced command becomes its own section, leaving our
# intended groups empty). An empty PS4 emits no prefix at all (bash does not
# fall back to a default), so the traced command itself starts the line — and
# every command we trace begins with `docker`, never a marker.
PS4=''

# The pre-command and post-command hooks bracket someone else's command, so
# their log groups are collapsed (~~~) to stay out of the way of it.
if [[ "$HOOK" == "command" ]]; then
  _GROUP="---"
  _RUN_GROUP="+++"
else
  _GROUP="~~~"
  _RUN_GROUP="~~~"
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

if plugin_read_list_into_result "BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT"; then
  for e in "${result[@]}"; do
    CREATE_ARGS+=(-e "$e")
  done
fi

if plugin_read_list_into_result "BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES"; then
  for v in "${result[@]}"; do
    if [[ "$v" == *:* ]]; then
      host="${v%%:*}"
      rest="${v#*:}"
      # Only `.` and `./…` are relative paths. A bare leading dot is part of the
      # filename (`.env`, `.git`), so treating it as relative mounted `<pwd>env`.
      if [[ "$host" == "." ]]; then
        host="$(pwd)"
      elif [[ "$host" == ./* ]]; then
        host="$(pwd)/${host#./}"
      fi
      v="${host}:${rest}"
    fi
    CREATE_ARGS+=(-v "$v")
  done
fi

if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_SSH_AGENT:-false}" == "true" ]]; then
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    CREATE_ARGS+=(-v "${SSH_AUTH_SOCK}:/run/ssh-agent")
    CREATE_ARGS+=(-e "SSH_AUTH_SOCK=/run/ssh-agent")
    # Carry the agent's host-key trust into the container as the global known_hosts.
    # Without it, git/ssh over SSH hits an interactive "authenticity of host ...
    # can't be established" prompt — and because the container is always allocated a
    # TTY (see --tty above), that prompt blocks forever instead of failing fast.
    # Mounting at /etc/ssh/ssh_known_hosts (rather than /root/.ssh/known_hosts) means
    # any container user trusts the host, not just root.
    KNOWN_HOSTS="${HOME:-/var/lib/buildkite-agent}/.ssh/known_hosts"
    if [[ -f "${KNOWN_HOSTS}" ]]; then
      CREATE_ARGS+=(-v "${KNOWN_HOSTS}:/etc/ssh/ssh_known_hosts:ro")
    fi
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
  # `compgen -e`, not `env`: `env` prints NAME=VALUE records separated by
  # newlines, so a variable whose value contains a newline (a commit message,
  # a multi-line BUILDKITE_COMMAND) makes each of its continuation lines look
  # like another record — and a line such as `BUILDKITE_FOO=1` inside a value
  # would be forwarded as if `BUILDKITE_FOO` were a real variable. `compgen -e`
  # lists the names of exported variables only, and a name can never contain a
  # newline, so one line is always exactly one name.
  while read -r key; do
    if [[ "$key" == "CI" || "$key" == "BUILDKITE" || "$key" == BUILDKITE_* ]]; then
      CREATE_ARGS+=(-e "$key")
    fi
  done < <(compgen -e)
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
  echo "$DOCKER_RUN_TMPDIR" > "/tmp/${CONTAINER_NAME}.tmpdir"
fi

if [[ -n "${BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND:-}" && -z "${BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND_0:-}" ]]; then
  echo "+++ Error: The command option must be an array, not a string. Use command: ['arg1', 'arg2']."
  exit 1
fi
CMD_ITEMS=()
if plugin_read_list_into_result "BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND"; then
  CMD_ITEMS=("${result[@]}")
fi
has_plugin_commands=false
[[ ${#CMD_ITEMS[@]} -gt 0 ]] && has_plugin_commands=true

# Only the command hook runs the step's command. Under pre-command and
# post-command it belongs to whoever owns the command hook — the agent, or
# another plugin — so it is not ours to run and cannot conflict with the
# plugin's own command. BUILDKITE_COMMAND is already exported by the time those
# hooks fire, so treating it as a conflict would fail every step that has both
# a command and this plugin bracketing it.
has_step_commands=false
if [[ "$HOOK" == "command" ]]; then
  [[ -n "${BUILDKITE_COMMAND:-}" ]] && has_step_commands=true

  if [[ "$has_step_commands" == "true" && "$has_plugin_commands" == "true" ]]; then
    echo "+++ Error: Cannot specify both step commands and plugin commands. Move commands to the step or to the plugin 'command' option, not both."
    exit 1
  fi
fi

# Determine shell (only applies to step commands)
SHELL_ARGS=()
shell_enabled=true
shell_explicitly_set=false
if [[ "${BUILDKITE_PLUGIN_DOCKER_RUN_SHELL:-}" =~ ^(false|off|0)$ ]]; then
  shell_enabled=false
elif [[ -n "${BUILDKITE_PLUGIN_DOCKER_RUN_SHELL_0:-}" ]]; then
  plugin_read_list_into_result "BUILDKITE_PLUGIN_DOCKER_RUN_SHELL"
  SHELL_ARGS=("${result[@]}")
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
