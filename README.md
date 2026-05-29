# Docker Run Buildkite Plugin

Run a command in a Docker image with phase-level timing and automatic cleanup. Each phase (pull, create, run) appears as a separate log group in Buildkite, making it easy to spot where time is spent. The container is always cleaned up, even if the command fails.

## Requirements

- Docker 25+

## Configuration

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `image` | string | ✓ | Docker image to run |
| `command` | string or array | — | Command and args to run in the container |
| `workdir` | string | — | Override working directory in the container |
| `entrypoint` | string | — | Override container entrypoint |
| `env` | array | — | Environment variables as `KEY=VALUE` |
| `volume` | array | — | Volume mounts as `host:container`. Relative host paths (starting with `.`) are resolved against `pwd`. |
| `docker_from_docker` | boolean | — | Mount the host Docker socket and a readable copy of the Docker config, enabling Docker-from-Docker. Socket path is derived from `DOCKER_HOST` (defaults to `unix:///var/run/docker.sock`). |

## Usage

Add the plugin to your pipeline:

```yaml
steps:
  - command: make test
    plugins:
      - jameslnewell/docker-run#v1.0.0:
          image: node:20
          workdir: /app
          volume:
            - /workspace:/app
          env:
            - CI=true
```

Run a command directly in Docker:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v1.0.0:
          image: ubuntu:24.04
          command:
            - bash
            - -c
            - "apt-get update && apt-get install -y curl"
```

Mount the current checkout and run tests with Docker-from-Docker enabled so the container can build and push images:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v1.0.0:
          image: node:20
          workdir: /workdir
          volume:
            - .:/workdir
            - /workdir/node_modules
          docker_from_docker: true
          env:
            - CI=true
```

Pass through AWS region environment variables:

```yaml
steps:
  - plugins:
      - jameslnewell/docker-run#v1.0.0:
          image: amazon/aws-cli:latest
          command: ecr get-login-password
          env:
            - AWS_REGION
            - AWS_DEFAULT_REGION
```

## How It Works

The plugin:

1. **Pull**: Downloads the Docker image (`docker pull`)
2. **Create**: Creates a container with your configuration (`docker create`)
3. **Run**: Starts and attaches to the container (`docker start --attach`)
4. **Cleanup**: Always removes the container on exit (`docker rm -f`)

Each phase is a separate log group in Buildkite, so you can see exactly where time is spent and fold/expand them independently.

## Other plugins that may be useful

- [docker-compose-run](https://github.com/jameslnewell/docker-compose-run-buildkite-plugin) — Run a docker compose service with phase-level timing and automatic cleanup
- [docker-compose-build](https://github.com/jameslnewell/docker-compose-build-buildkite-plugin) — Build and push a docker compose service using `docker buildx bake`

## Testing

Tests are written using [bats](https://github.com/bats-core/bats-core). The unit tests stub Docker commands and require [bats-support](https://github.com/bats-core/bats-support), [bats-assert](https://github.com/bats-core/bats-assert), and [bats-mock](https://github.com/buildkite-plugins/bats-mock).

Install the dependencies (macOS):

```bash
brew install bats-core bats-support bats-assert
# bats-mock is not in Homebrew — clone it alongside the others:
git clone https://github.com/buildkite-plugins/bats-mock "$(brew --prefix)/lib/bats-mock"
```

Run the unit tests (no Docker required):

```bash
BATS_LIB_PATH="$(brew --prefix)/lib" bats tests/command.bats tests/pre-exit.bats
```

Run the integration tests (requires Docker):

```bash
bats tests/integration.bats
```
