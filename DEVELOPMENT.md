# Development Guide

## Configuration Naming Conventions

This plugin aligns its configuration option names with the [Docker Compose Specification](https://compose-spec.io/) to provide a familiar API for users who work with `docker-compose.yml` files.

### Naming Alignment with Compose Spec

| Docker Compose field | Plugin YAML option | Environment variable | Purpose |
|-----|-----|-----|-----|
| `environment` | `environment` | `BUILDKITE_PLUGIN_DOCKER_RUN_ENVIRONMENT` | Environment variables for the container |
| `volumes` | `volumes` | `BUILDKITE_PLUGIN_DOCKER_RUN_VOLUMES` | Volume mounts for the container |

### Example Configuration

```yaml
steps:
  - name: Run tests
    command: |
      docker-compose run app npm test
    plugins:
      - docker#v5.0.0:
          image: node:18
          environment:
            - NODE_ENV=test
            - DEBUG=app:*
          volumes:
            - ./src:/app/src:ro
            - ./node_modules:/app/node_modules
```

### Non-Spec Options

Options not defined in the Compose spec follow CLI conventions:
- `command` - command to run in the container
- `entrypoint` - override the container entrypoint
- `workdir` - working directory in the container
- `docker_from_docker` - enable Docker-in-Docker support

## Related Documentation

- [Docker Compose Specification](https://compose-spec.io/)
- [Plugin Configuration Reference](./README.md)
