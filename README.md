# Docker Run Buildkite Plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that runs a step's command in a Docker image, with phase-level timing and automatic cleanup.

Each phase (pull, create, run) is a separate log group in Buildkite, so it's easy to see where the time went. The container is always removed on exit, even when the command fails.

## Requirements

- The `docker` CLI available to the Buildkite agent. The plugin only uses `docker pull`, `docker create`, `docker start` and `docker rm`.
- `propagate-buildkite-agent` additionally requires the agent socket at `/run/buildkite-agent/buildkite-agent.sock`.

## Usage

Run the step's command inside an image. By default the checkout is mounted at `/workdir` and the command is wrapped in `/bin/sh -e -c`:

```yaml
steps:
  - command: make test
    plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: node:20
          environment:
            - CI=true
```

Run a command defined by the plugin instead of the step. Each array item is one argv token — there is no shell, so `&&`, pipes and globs are not interpreted:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: ubuntu:24.04
          command:
            - bash
            - -c
            - "apt-get update && apt-get install -y curl"
```

A single array item may span multiple lines, so a whole script can be handed to a shell. Name the shell with the `shell` option and the script is the only thing left in `command`:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.14.0:
          image: hashicorp/terraform:1.15
          shell: ["/bin/sh", "-ec"]
          command:
            - |
              cd terraform/production
              terraform init
              terraform plan
```

Naming the shell inside `command` works too — `command: ["/bin/sh", "-ec", "<script>"]` — but the `shell` option is what the official `docker` plugin uses, and it keeps the two concerns apart.

Keep the container's `node_modules` out of the mounted checkout with an anonymous volume:

```yaml
steps:
  - command: npm ci && npm test
    plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: node:20
          volumes:
            - /workdir/node_modules
```

Build and push images from inside the container by propagating the host Docker socket:

```yaml
steps:
  - command: ./scripts/build-and-push.sh
    plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: docker:27
          propagate-docker: true
```

Clone private repositories by propagating the agent's SSH agent:

```yaml
steps:
  - command: npm ci
    plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: node:20
          propagate-ssh-agent: true
```

Pass credentials to a step that talks to AWS. The image's `aws` entrypoint is left in place, so `command` only supplies its arguments:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.16.0:
          image: amazon/aws-cli:latest
          command: ["ecr", "get-login-password"]
          propagate-aws: true
```

Bracket the step's own command with setup and teardown by listing the plugin twice — `hook: pre-command` runs before the step, `hook: post-command` after it. In both modes the plugin only runs its own `command`, so the step keeps its command:

```yaml
steps:
  - command: npm test
    plugins:
      - jameslnewell/docker-run#v0.16.0:
          hook: pre-command
          image: amazon/aws-cli:latest
          propagate-aws: true
          command: ["s3", "cp", "s3://my-bucket/.env", ".env"]
      - jameslnewell/docker-run#v0.16.0:
          hook: post-command
          image: amazon/aws-cli:latest
          propagate-aws: true
          command: ["s3", "cp", "junit.xml", "s3://my-bucket/reports/"]
```

`post-command` runs whether the step's command passed or failed, which is what you want for collecting reports — but it means a teardown that can't cope with a failed step needs to check for itself. With `propagate-buildkite-environment: true` the container gets `BUILDKITE_COMMAND_EXIT_STATUS` to branch on.

`pre-command` also works when the command hook belongs to another plugin — for example fetching secrets before a `docker-compose-run` step:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.16.0:
          hook: pre-command
          image: amazon/aws-cli:latest
          propagate-aws: true
          command: ["s3", "cp", "s3://my-bucket/.env", ".env"]
      - jameslnewell/docker-compose-run#v0.14.1:
          service: test
          command: ["npm", "test"]
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `image` | string | — | **Required.** Docker image to run. |
| `command` | array | — | Argv passed as the container CMD. Each array item is one token, and an item may span multiple lines. Not wrapped in a shell unless `shell` names one. Cannot be combined with the step's `command` — except under `hook: pre-command` or `hook: post-command`, where the step's command is not the plugin's to run. |
| `shell` | array or boolean | `["/bin/sh", "-e", "-c"]` for the step's command; none for the plugin's `command` | Shell to wrap the command in. Setting it explicitly wraps the plugin's `command` too, which is how a multi-line script is run. Set to `false` to pass the step's command through unwrapped. |
| `workdir` | string | `/workdir` when `mount-checkout` is enabled, otherwise the image's | Working directory inside the container. |
| `entrypoint` | string | — | Override the image's `ENTRYPOINT`. Any value — including `""` — suppresses the *default* shell wrapping; setting `shell` explicitly turns it back on. Matches the official `docker` plugin. Use `""` to clear an image's entrypoint while passing `command` args directly. |
| `mount-checkout` | boolean | `true` | Mount the agent checkout directory at the working directory inside the container. |
| `environment` | array | — | Environment variables as `KEY` (propagated from the agent) or `KEY=VALUE`. |
| `volumes` | array | — | Volume mounts as `host:container`, or a bare container path for an anonymous volume. Host paths of `.` or beginning with `./` are resolved against `pwd`, so `.:/app` mounts the checkout. Every other host path — including dotfiles like `.env` and named volumes — is passed to Docker unchanged. |
| `propagate-docker` | boolean | `false` | Mount the host Docker socket and a readable copy of the Docker config, enabling Docker-from-Docker without `userns:host`. The socket path is derived from `DOCKER_HOST` (default `unix:///var/run/docker.sock`); for a TCP daemon, `DOCKER_HOST` is passed through instead. |
| `propagate-ssh-agent` | boolean | `false` | Forward the agent's SSH agent socket to `/run/ssh-agent` and set `SSH_AUTH_SOCK`. Also mounts the agent's `~/.ssh/known_hosts` (when present) at `/etc/ssh/ssh_known_hosts`, so `git`/`ssh` trust known hosts instead of hanging on an interactive host-key prompt. |
| `propagate-aws` | boolean | `false` | Propagate `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`. |
| `propagate-buildkite-agent` | boolean | `false` | Mount the Buildkite agent socket and propagate `BUILDKITE_AGENT_ACCESS_TOKEN`, so the container can run `buildkite-agent` commands. |
| `propagate-buildkite-environment` | boolean | `false` | Propagate `CI`, `BUILDKITE` and every `BUILDKITE_*` variable from the agent. |
| `hook` | `command`, `pre-command` or `post-command` | `command` | Buildkite hook phase to run in. Use `pre-command` to run as setup before the main command hook, or `post-command` to run as teardown after it. Both collapse their log groups so they stay out of the way, and both run only the plugin's `command`. |

`additionalProperties` is disabled, so an unrecognised or misspelled option fails validation rather than being silently ignored.

### Commands and shells

Under the default `hook: command`, the container's command comes from either the step or the plugin, never both:

- **Step command** — `BUILDKITE_COMMAND` is wrapped in `shell` (`/bin/sh -e -c` by default) and passed as the container CMD. This is what most steps want, because it supports multi-line scripts, pipes and `&&`.
- **Plugin `command`** — the array is passed as argv. There is no shell unless `shell` names one, in which case the shell is prepended and the array becomes its arguments. Use it for steps that have no command of their own.

Shell wrapping resolves the same way as the official `docker` plugin: off unless something turns it on. A step command turns it on; so does naming a `shell`. An `entrypoint` turns it back off, and an explicit `shell` overrides that in turn.

Setting both `entrypoint` and `shell` composes rather than conflicts, because Docker runs the entrypoint with the container's arguments appended to it. `entrypoint: ""` clears the image's entrypoint so the shell runs directly, and a wrapper entrypoint that execs its arguments — `tini`, `dumb-init`, `env`, `gosu` — runs the shell in turn. An entrypoint that does *not* exec its arguments will instead receive the shell's path as an argument of its own, which is rarely what you want.

The plugin fails the step, rather than silently picking one, when the configuration is ambiguous:

- Both a step command and the plugin's `command` are set.
- `command` is given as a string instead of an array.
- `shell` is given as a string instead of an array or `false`.
- `shell` is set as an array while `entrypoint` is also set, since `entrypoint` suppresses shell wrapping.

The first of those does not apply to `hook: pre-command` or `hook: post-command`. There the step's command belongs to the command hook — the agent's, or another plugin's — so it is never a candidate for the container's command and cannot conflict with the plugin's `command`. A `pre-command` or `post-command` entry with no plugin `command` runs the image's own `CMD`.

## How it works

1. **Pull** — `docker pull <image>`
2. **Create** — `docker create` with the configured workdir, mounts, environment and command. A TTY is always allocated, so tools that colourise their output when attached to a terminal keep doing so in the build log.
3. **Run** — `docker start --attach`, streaming the container's output into the step log
4. **Cleanup** — the `pre-exit` hook always runs `docker rm -f`, and removes the temporary Docker config copy created by `propagate-docker`

Each phase is its own log group, so you can fold and expand them independently and see exactly where time is spent.

Containers are named `docker-run-buildkite-plugin-<job id>`, with the hook phase appended under `pre-command` and `post-command`. That keeps a step that lists the plugin more than once from reusing a name that is still taken — containers live until `pre-exit`, which Buildkite runs once per plugin entry, so each run cleans up its own.

## Other plugins that may be useful

- [docker-compose-run](https://github.com/jameslnewell/docker-compose-run-buildkite-plugin) — Run a docker compose service with phase-level timing and automatic cleanup
- [docker-compose-build](https://github.com/jameslnewell/docker-compose-build-buildkite-plugin) — Build and push a docker compose service using `docker buildx bake`

## Contributing

See [DEVELOPMENT.md](./DEVELOPMENT.md) for how to run the tests and cut a release.
