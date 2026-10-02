# Docker Run Buildkite Plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that runs a step's command in a Docker image, with phase-level timing and automatic cleanup.

Each phase (pull, create, run) is a separate log group in Buildkite, so it's easy to see where the time went. The container is always removed on exit, even when the command fails.

## Requirements

- The `docker` CLI available to the Buildkite agent. The plugin only uses `docker pull`, `docker create`, `docker start` and `docker rm`, plus `docker container inspect` and `docker cp` when `copy-out` is set.
- `propagate-buildkite-agent` additionally requires the agent socket at `/run/buildkite-agent/buildkite-agent.sock`.

## Usage

Run the step's command inside an image. By default the checkout is mounted at `/workdir` and the command is wrapped in `/bin/sh -e -c`:

```yaml
steps:
  - command: make test
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: node:20
          environment:
            - CI=true
```

Run a command defined by the plugin instead of the step. Each array item is one argv token — there is no shell, so `&&`, pipes and globs are not interpreted:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.18.0:
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
      - jameslnewell/docker-run#v0.18.0:
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
      - jameslnewell/docker-run#v0.18.0:
          image: node:20
          volumes:
            - /workdir/node_modules
```

Build and push images from inside the container. `propagate-docker-daemon` hands it the host Docker daemon; `propagate-docker-config` hands it the agent's registry credentials:

```yaml
steps:
  - command: ./scripts/build-and-push.sh
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: docker:27
          propagate-docker-daemon: true
          propagate-docker-config: true
```

Ask for only the half the step uses. A step that builds an image and hands it to a later step to push needs the daemon and no credentials at all:

```yaml
steps:
  - command: docker build -t app:$BUILDKITE_BUILD_NUMBER .
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: docker:27
          propagate-docker-daemon: true
```

And a tool that copies image tags between registries — `crane`, `skopeo`, `regctl` — talks to the registry over HTTP and never to a Docker daemon, so it wants the credentials on their own. These images run as a non-root user, which is what `DOCKER_CONFIG` makes workable:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: gcr.io/go-containerregistry/crane:v0.22.0
          command: ["copy", "my-registry/app:build-42", "my-registry/app:v1.2.3"]
          propagate-docker-config: true
          # the copy is registry-to-registry; it never reads the checkout
          mount-checkout: false
```

Clone private repositories by propagating the agent's SSH agent:

```yaml
steps:
  - command: npm ci
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: node:20
          propagate-ssh-agent: true
```

Pass credentials to a step that talks to AWS. The image's `aws` entrypoint is left in place, so `command` only supplies its arguments:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: amazon/aws-cli:latest
          command: ["ecr", "get-login-password"]
          propagate-aws: true
```

Copy what the command wrote out of the container, for a later plugin to upload. `from` is relative to the container's working directory, and `to` to the job's:

```yaml
steps:
  - command: npm test -- --coverage
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          image: my-registry/app:build-42
          # the app is baked into the image, so there is no checkout to write into
          mount-checkout: false
          copy-out:
            - coverage:coverage
      - artifacts#v1.10.0:
          upload: "coverage/**/*"
```

`copy-out` is not in older releases, so pin one that includes it. See [Copying output out of the container](#copying-output-out-of-the-container).

Bracket the step's own command with setup and teardown by listing the plugin twice — `hook: pre-command` runs before the step, `hook: post-command` after it. In both modes the plugin only runs its own `command`, so the step keeps its command:

```yaml
steps:
  - command: npm test
    plugins:
      - jameslnewell/docker-run#v0.18.0:
          hook: pre-command
          image: amazon/aws-cli:latest
          propagate-aws: true
          command: ["s3", "cp", "s3://my-bucket/.env", ".env"]
      - jameslnewell/docker-run#v0.18.0:
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
      - jameslnewell/docker-run#v0.18.0:
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
| `copy-out` | array | — | Paths to copy out of the container once the command exits, as `from:to`. A relative `from` is resolved against the container's working directory. `to` is a path inside the job's working directory, and replaces whatever is already there. See [Copying output out of the container](#copying-output-out-of-the-container). |
| `propagate-docker-daemon` | boolean | `false` | Give the container access to the host Docker daemon, enabling Docker-from-Docker without `userns:host`. The socket path is derived from `DOCKER_HOST` (default `unix:///var/run/docker.sock`); for a TCP daemon there is no socket to mount, so `DOCKER_HOST` is passed through instead. |
| `propagate-docker-config` | boolean | `false` | Give the container the agent's registry credentials, so it can pull and push without logging in first. A readable copy of the agent's Docker config is mounted at `/run/docker-config/config.json`, with `DOCKER_CONFIG` naming that directory. See [The propagated Docker config](#the-propagated-docker-config). |
| `propagate-docker` | boolean | `false` | **Deprecated.** Means `propagate-docker-daemon` and `propagate-docker-config` at once. Warns at runtime, and setting it to `true` alongside either of them is an error. See [Migrating from `propagate-docker`](#migrating-from-propagate-docker). |
| `propagate-ssh-agent` | boolean | `false` | Forward the agent's SSH agent socket to `/run/ssh-agent` and set `SSH_AUTH_SOCK`. Also mounts the agent's `~/.ssh/known_hosts` (when present) at `/etc/ssh/ssh_known_hosts`, so `git`/`ssh` trust known hosts instead of hanging on an interactive host-key prompt. |
| `propagate-aws` | boolean | `false` | Propagate `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`. |
| `propagate-buildkite-agent` | boolean | `false` | Mount the Buildkite agent socket and propagate `BUILDKITE_AGENT_ACCESS_TOKEN`, so the container can run `buildkite-agent` commands. |
| `propagate-buildkite-environment` | boolean | `false` | Propagate `CI`, `BUILDKITE` and every `BUILDKITE_*` variable from the agent. |
| `hook` | `command`, `pre-command` or `post-command` | `command` | Buildkite hook phase to run in. Use `pre-command` to run as setup before the main command hook, or `post-command` to run as teardown after it. Both collapse their log groups so they stay out of the way, and both run only the plugin's `command`. |

`additionalProperties` is disabled, so an unrecognised or misspelled option fails validation rather than being silently ignored.

### The propagated Docker config

`propagate-docker-config` copies the agent's `config.json` into a job-scoped
temp directory, mounts the copy at `/run/docker-config/config.json`, and sets
`DOCKER_CONFIG` to `/run/docker-config`. The copy is removed by `pre-exit`; the
agent's own `~/.docker` is never mounted, so nothing in the container can overwrite the
credentials the agent goes on using.

- **`DOCKER_CONFIG` is set by the plugin**, after the step's own `environment`,
  so a `DOCKER_CONFIG` set there does not take effect. `docker`, `crane`,
  `skopeo` and `regctl` all read it.
- **A container that does not run as root can read the credentials**, which is
  the point of `DOCKER_CONFIG` over `/root/.docker`: `/root` is `0700`, so a
  distroless image with a non-root `USER` could never reach a config mounted
  under it. The mount's parent does not exist in the image, so the daemon
  creates it root-owned `0755` and any container user can traverse it.
- **The container cannot rewrite the propagated config.** It is a bind-mounted
  file, and `docker login` saves credentials by renaming a temp file over
  `config.json`, which fails with `EBUSY` against one. A step that needs to run
  its own `docker login` should take `propagate-docker-daemon` and leave this
  off, so that login has an ordinary path to write to.
- **Only `config.json` is copied.** An agent whose config delegates to a
  credential helper (`credsStore` or `credHelpers`, as `docker-credential-ecr-login`
  setups do) needs that helper binary present in the image as well — a
  distroless image has no helpers and fails with `executable file not found`.

### Copying output out of the container

`copy-out` copies files or directories out of the stopped container into the
job's working directory, where a later plugin or hook can pick them up. It is
for steps that do not mount the checkout — an image with the application baked
in — and for output that a bind mount cannot carry: a tool that removes and
recreates its output directory cannot remove a mount point.

Each entry is `<from>:<to>`:

- **`from` is a path in the container.** If it is a symlink, what it points to
  is copied. A relative path is resolved against the container's working
  directory: the `workdir` option, `mount-checkout`'s `/workdir`, or the
  image's `WORKDIR`. An image that sets none ran its command in `/`, so that is
  what `from` is resolved against. An absolute path is used as is. (`docker cp`
  on its own resolves a relative path against `/`.)
- **`to` is a path inside the job's working directory.** Its parent directories
  are created, and a leading `./` is accepted. Whatever is already at `to` is
  replaced rather than copied into, so output left over from an earlier job is
  never mixed with this one's or left with this one's nested inside it. Because
  it is replaced, `to` cannot be absolute, have a `.` or `..` component, or be
  the working directory itself.
- **The copy runs in the hook that ran the container**, as soon as the
  container exits: the `command` hook by default, or `pre-command` or
  `post-command` under `hook`. From the `command` and `pre-command` hooks, the
  output is on the agent before any `post-command` hook runs, whatever order
  the agent runs them in. Under `hook: post-command` the copy is itself a
  `post-command` hook, so a plugin that consumes the output has to run its
  `post-command` after this one. Buildkite agent v4 runs `post-command` hooks
  in reverse plugin order, which means listing that plugin before this one.
- **The hook exits with the command's status**, and the copy happens whether
  the command passed or failed, so a failing test run still hands over its
  report.
- **A `from` the container does not have is logged and skipped.** Any other
  failure to copy fails the hook. A failed command keeps its own exit status.
- **A `to` that already holds the same files is left in place.** With the
  default `mount-checkout`, the container's `/workdir/coverage` is the agent's
  `coverage`, so `coverage:coverage` finds the output already there and says so
  in the log. The same `copy-out` therefore works whether or not a step mounts
  the checkout.

An entry that is not exactly `<from>:<to>` fails the hook before the image is
pulled.

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
- `propagate-docker: true` is set alongside `propagate-docker-daemon` or `propagate-docker-config`.

The first of those does not apply to `hook: pre-command` or `hook: post-command`. There the step's command belongs to the command hook — the agent's, or another plugin's — so it is never a candidate for the container's command and cannot conflict with the plugin's `command`. A `pre-command` or `post-command` entry with no plugin `command` runs the image's own `CMD`.

### Migrating from `propagate-docker`

`propagate-docker` bundles two unrelated capabilities — access to the host Docker **daemon**, and the agent's registry **credentials** — and most steps want one of them. A step that copies image tags between registries needs the credentials and never talks to a daemon; a step that builds an image locally needs the daemon and not the credentials. The difference is worth drawing, because anything that can reach the host's Docker socket can mount `/` into a privileged container, so a step handed the daemon it did not ask for is handed root on the agent.

Replace it with whichever halves the step actually uses:

```yaml
# Before
propagate-docker: true

# After — building and pushing needs both
propagate-docker-daemon: true
propagate-docker-config: true

# After — copying tags, or pushing an image built elsewhere, needs the credentials alone
propagate-docker-config: true

# After — building locally, with no registry to authenticate against, needs the daemon alone
propagate-docker-daemon: true
```

The config half no longer mounts `config.json` at `/root/.docker/config.json`; it mounts it at `/run/docker-config/config.json` and sets `DOCKER_CONFIG`, as [The propagated Docker config](#the-propagated-docker-config) describes. A step that reads the credentials by path rather than through `DOCKER_CONFIG` has to be pointed at the new one.

`propagate-docker` still works and still means both halves. It warns whenever it is used, and `propagate-docker: true` alongside either new option fails the step rather than quietly picking a winner — an explicit `propagate-docker: false` alongside one of them is an opt-out with only one reading, so it only warns. It will be removed in a future major release; consumers pin exact tags, so nothing is forced off it in the meantime.

## How it works

1. **Pull** — `docker pull <image>`
2. **Create** — `docker create` with the configured workdir, mounts, environment and command. A TTY is always allocated, so tools that colourise their output when attached to a terminal keep doing so in the build log.
3. **Run** — `docker start --attach`, streaming the container's output into the step log
4. **Copy out** — only with `copy-out`: `docker container inspect` for the container's working directory, then `docker cp` for each entry
5. **Cleanup** — the `pre-exit` hook always runs `docker rm -f`, and removes the temporary Docker config directory created by `propagate-docker-config` and any scratch directory a killed `copy-out` left in the working directory

Each phase is its own log group, so you can fold and expand them independently and see exactly where time is spent.

Containers are named `docker-run-buildkite-plugin-<job id>`, with the hook phase appended under `pre-command` and `post-command`. That keeps a step that lists the plugin more than once from reusing a name that is still taken — containers live until `pre-exit`, which Buildkite runs once per plugin entry, so each run cleans up its own.

## Other plugins that may be useful

- [docker-compose-run](https://github.com/jameslnewell/docker-compose-run-buildkite-plugin) — Run a docker compose service with phase-level timing and automatic cleanup
- [docker-compose-build](https://github.com/jameslnewell/docker-compose-build-buildkite-plugin) — Build and push a docker compose service using `docker buildx bake`

## Contributing

See [DEVELOPMENT.md](./DEVELOPMENT.md) for how to run the tests and cut a release.
