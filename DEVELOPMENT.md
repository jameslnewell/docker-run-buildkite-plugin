# Development Guide

## Configuration Naming Conventions

This plugin aligns its configuration option names with the [Docker Compose Specification](https://compose-spec.io/) to provide a familiar API for users who work with `docker-compose.yml` files.

### Naming Alignment with Compose Spec

| Docker Compose field | Plugin YAML option | Environment variable | Purpose |
|-----|-----|-----|-----|
| `environment` | `environment` | `BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT` | Environment variables for the container |
| `volumes` | `volumes` | `BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES` | Volume mounts for the container |
| `entrypoint` | `entrypoint` | `BUILDKITE_PLUGIN_DOCKER_RUN_ENTRYPOINT` | Override the image's entrypoint |
| `command` | `command` | `BUILDKITE_PLUGIN_DOCKER_RUN_COMMAND` | Argv passed as the container CMD |

### Non-Spec Options

Options not defined in the Compose spec follow either the Docker CLI's naming or the official [`docker` Buildkite plugin](https://github.com/buildkite-plugins/docker-buildkite-plugin)'s naming, so users moving between plugins don't have to relearn them:

| Plugin YAML option | Environment variable | Purpose |
|-----|-----|-----|
| `image` | `BUILDKITE_PLUGIN_DOCKER_RUN_IMAGE` | Image to run |
| `workdir` | `BUILDKITE_PLUGIN_DOCKER_RUN_WORKDIR` | Working directory in the container |
| `shell` | `BUILDKITE_PLUGIN_DOCKER_RUN_SHELL` | Shell used to wrap the step's command |
| `mount-checkout` | `BUILDKITE_PLUGIN_DOCKER_RUN_MOUNT_CHECKOUT` | Mount the agent checkout as the working directory |
| `propagate-docker` | `BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_DOCKER` | Mount the host Docker socket and config |
| `propagate-ssh-agent` | `BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_SSH_AGENT` | Forward the host SSH agent and known hosts |
| `propagate-aws` | `BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_AWS` | Propagate AWS credential and region env vars |
| `propagate-buildkite-agent` | `BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_AGENT` | Mount the Buildkite agent socket and token |
| `propagate-buildkite-environment` | `BUILDKITE_PLUGIN_DOCKER_RUN_PROPAGATE_BUILDKITE_ENVIRONMENT` | Propagate `CI`, `BUILDKITE` and `BUILDKITE_*` |
| `hook` | `BUILDKITE_PLUGIN_DOCKER_RUN_HOOK` | Hook phase to run in (`command`, `pre-command` or `post-command`) |

Array options are read with `plugin_read_list_into_result` in [`lib/shared.bash`](./lib/shared.bash), which reads the `_0`, `_1`, … indexed variables the agent exports for YAML arrays, falls back to the unindexed variable for scalars, and returns non-zero when the option is unset. It appends into the global `result` array — like the official [`docker`](https://github.com/buildkite-plugins/docker-buildkite-plugin) plugin's helper of the same name — rather than printing values for `mapfile` to re-read, because an item may itself contain newlines (a whole shell script passed as one `command:` entry) and a newline-delimited round-trip would split it into one argv entry per line.

Every hook file is a router: `hooks/<phase>` exits immediately unless the `hook` option selects that phase, then sources [`lib/run.bash`](./lib/run.bash), which does the actual work for all three. Adding a phase means adding a router and extending the `hook` enum — the run logic branches only on `command` versus the rest.

## Testing

Run the full suite the same way CI does — the [`buildkite/plugin-tester`](https://github.com/buildkite-plugins/buildkite-plugin-tester) image bundles bats and its helper libraries:

```bash
docker run --rm -v "$PWD:/plugin:ro" buildkite/plugin-tester
```

To run [bats](https://github.com/bats-core/bats-core) directly on macOS, install the helpers first — the unit tests stub Docker and need [bats-support](https://github.com/bats-core/bats-support), [bats-assert](https://github.com/bats-core/bats-assert) and [bats-mock](https://github.com/buildkite-plugins/bats-mock):

```bash
brew tap bats-core/bats-core
brew install bash bats-core bats-core/bats-core/bats-support bats-core/bats-core/bats-assert
# bats-mock is not in Homebrew — clone it alongside the others:
git clone https://github.com/buildkite-plugins/bats-mock "$(brew --prefix)/lib/bats-mock"
```

Unit tests (no Docker required):

```bash
PATH="$(brew --prefix)/bin:$PATH" BATS_LIB_PATH="$(brew --prefix)/lib" bats tests/command.bats tests/pre-command.bats tests/pre-exit.bats
```

Integration tests (requires Docker):

```bash
PATH="$(brew --prefix)/bin:$PATH" BATS_LIB_PATH="$(brew --prefix)/lib" bats tests/integration.bats
```

> **Keep the `PATH` prefix on macOS — it is not just for finding bats.** Under the
> system bash (3.2), bats does not abort a test at the first failed assertion: only
> the last command in the test body decides the result, so a test can report `ok`
> while an assertion in the middle of it failed. The same file, same bats, on bash
> 5.2 fails as it should. `buildkite/plugin-tester` ships its own bash and is
> unaffected.

### What runs where

`buildkite/plugin-tester` has no `docker` CLI, so `tests/integration.bats` skips in
it — which is why running only that image is not enough to know the suite passed.

CI covers both: `.github/workflows/test.yml` runs the suite in `plugin-tester`
(keeping that path honest, since it is what this guide tells you to use locally)
*and* runs it natively on the runner, where a `docker` CLI and daemon exist, so
every test executes. That second job fails if any test reports a skip.

## Releasing

1. Merge all changes to `main`
2. Go to **Actions → Create Release → Run workflow**
3. Enter the version (e.g. `v0.15.0`) and click **Run workflow**

The workflow will tag the commit, push the tag, and create a GitHub release with an auto-generated changelog.

## Related Documentation

- [Docker Compose Specification](https://compose-spec.io/)
- [Plugin Configuration Reference](./README.md)
