# llama.cpp Port Axis — Design

Date: 2026-11-10

## Intent

The listening port appears twice in `Dockerfile.rocm` as the literal `8080`: the server's `LLAMA_ARG_PORT` environment variable and the healthcheck URL. llama.cpp's compiled default changed from 8080 in v0.5.0 (`common/common.h:620`) to 9931 in v0.8.0 (`common/common.h:632`). The official v0.8.0 build recipes pin the port back to 8080 (`ENV LLAMA_ARG_PORT=8080` plus a hardcoded 8080 healthcheck in `.devops/rocm.Dockerfile`), so the drop-in target remains 8080 — but a future version whose official image serves a different port would force a `Dockerfile.rocm` edit. The port should be owned by the llama.cpp version configuration file, so one value drives both the server and the healthcheck probe.

## Goals

### The version file owns the port

`conf/llamacpp-v0.5.0.env` sets `LLAMA_ARG_PORT=8080`; the key is owned by the `llamacpp` axis in `build-rocm.sh` and is emitted as `--build-arg LLAMA_ARG_PORT=8080`.

The build argument is emitted from the version file
```gherkin
Scenario: The version file's port reaches the build as a build argument
  Given conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When build-rocm.sh resolves the four configuration files with --dry-run
  Then the emitted arguments contain --build-arg LLAMA_ARG_PORT=8080
```

### A stray neutral copy loses

The existing ownership rule applies unchanged: a `LLAMA_ARG_PORT` copy in `conf/build-config.env` (or another axis file) is discarded with a warning naming the `llamacpp` axis.

The version file wins a collision
```gherkin
Scenario: A stray LLAMA_ARG_PORT in the neutral file loses to the version file
  Given a neutral configuration file sets LLAMA_ARG_PORT=9999
  And conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When build-rocm.sh resolves the configuration
  Then the emitted arguments contain --build-arg LLAMA_ARG_PORT=8080
  And the emitted arguments do not contain --build-arg LLAMA_ARG_PORT=9999
  And stderr reports that the copy does not own the llamacpp axis
```

### The runtime stage derives the environment from the build argument

`Dockerfile.rocm`'s runtime stage declares `ARG LLAMA_ARG_PORT=8080` and sets `ENV LLAMA_ARG_PORT=${LLAMA_ARG_PORT}`, replacing the hardcoded `ENV LLAMA_ARG_PORT=8080`.

The environment value comes from the argument
```gherkin
Scenario: The runtime stage derives LLAMA_ARG_PORT from a declared build argument
  Given the runtime stage of Dockerfile.rocm
  When the file is inspected
  Then it declares ARG LLAMA_ARG_PORT=8080
  And it contains ENV LLAMA_ARG_PORT=${LLAMA_ARG_PORT}
  And it contains no ENV LLAMA_ARG_PORT=8080 literal
```

### The healthcheck probes the same value

The healthcheck becomes shell form: `HEALTHCHECK CMD curl -f "http://localhost:${LLAMA_ARG_PORT}/health"`. Docker does not expand variables in exec-form healthchecks (verified: the literal survives into the image config); the shell form expands at container runtime.

The probe follows the version-owned port
```gherkin
Scenario: The healthcheck probes the version-owned port
  Given the runtime stage of Dockerfile.rocm
  When the healthcheck instruction is inspected
  Then it contains HEALTHCHECK CMD curl -f "http://localhost:${LLAMA_ARG_PORT}/health"
  And no healthcheck instruction contains a numeric localhost port
```

### The Dockerfile default and the version file agree

For direct docker builds that bypass `build-rocm.sh`, the ARG default is 8080 and matches the v0.5.0 version file.

The defaults cannot drift
```gherkin
Scenario: The ARG default matches the version file
  Given conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When the default of ARG LLAMA_ARG_PORT in Dockerfile.rocm is read
  Then it equals 8080
```

### The documentation describes the mechanism

The build guide's port section and the README's llama.cpp versions table describe the version-owned port, the shell healthcheck's behaviour under an `-e LLAMA_ARG_PORT` override, and the `--port` override caveat.

The guide states where the port comes from
```gherkin
Scenario: The build guide documents the version-owned port
  Given docs/local-build-guide.md
  When the Ports and the healthcheck section is read
  Then it states the port comes from the llama.cpp version configuration file
```

## Constraints

- The image remains a 1:1 drop-in for the official image: same entrypoint (`/app/llama-server`), same default port (8080), same HTTP API.
- No `CMD` and no `--port` argv change. `ENV LLAMA_ARG_PORT` is upstream's own mechanism for setting `--port` (`.set_env("LLAMA_ARG_PORT")` in `common/arg.cpp`), and the entrypoint stays identical to the official image.
- `Dockerfile.rocm` changes, so `VERSION` iterates 1.1.1 → 1.1.2 per CONTRIBUTING.

## Non-goals

- No exec-form healthcheck with a `sh -c` wrapper; it diverges from the official form as much as the shell form does and adds noise.
- No `conf/llamacpp-v0.8.0.env`; adding the v0.8.0 version file belongs to issue #9.
- No runtime port discovery; the port is fixed at build time by the version file.

## Decisions

- Approach chosen: version-file key → build arg → `ENV` → shell-form healthcheck. The alternative (keep the official literal exec-form healthcheck and parameterise only the `ENV`) was rejected because the probe port would remain a hand-maintained duplicate, so the version file would not actually own it.
- Trade-off accepted: `docker inspect` reports `CMD-SHELL` instead of the official `CMD` array. Behaviour is identical for the default image, and a runtime `-e LLAMA_ARG_PORT=<port>` now moves both the server and the probe.
- Key name `LLAMA_ARG_PORT` matches the upstream environment variable, so no name mapping is introduced.

## What's left to the builder

- Exact test assertions and their wording.
- Placement of the build-guide prose and the README table row.
