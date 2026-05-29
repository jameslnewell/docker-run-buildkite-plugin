# Docker Run Buildkite Plugin

Run a command in a Docker image with phase-level timing and automatic cleanup. Each phase (pull, create, run) appears as a separate log group in Buildkite, making it easy to spot where time is spent. The container is always cleaned up, even if the command fails.

## Requirements

- Docker 25+

## Configuration

| Option | Type | Description | Required |
|--------|------|-------------|----------|
| `image` | string | Docker image to run | Yes |
| `command` | string or array | Command and args to run in the container | No |
| `workdir` | string | Override working directory in the container | No |
| `entrypoint` | string | Override container entrypoint | No |
| `env` | array | Environment variables as `KEY=VALUE` | No |
| `volume` | array | Volume mounts as `host:container` | No |

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

## How It Works

The plugin:

1. **Pull**: Downloads the Docker image (`docker pull`)
2. **Create**: Creates a container with your configuration (`docker create`)
3. **Run**: Starts and attaches to the container (`docker start --attach`)
4. **Cleanup**: Always removes the container on exit (`docker rm -f`)

Each phase is a separate log group in Buildkite, so you can see exactly where time is spent and fold/expand them independently.
