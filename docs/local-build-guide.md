# Local build guide

## Prerequisites

- Docker with Compose v2
- The **AMD Container Toolkit**, so `docker` exposes the GPU
- An amdgpu host driver on 30.x or 31.x (ROCm release numbers and amdgpu
  driver numbers are separate schemes)
- A llama.cpp source checkout is fetched automatically at the tag named by
  `LLAMA_CPP_VERSION` (cached under `llama.cpp/<tag>/`).
  Pass `--source /path/to/llama.cpp` to build from a local tree instead.

## Building

All four configuration files are required. The script rejects a partial
invocation rather than guessing which axis was meant. The source tree is
fetched automatically; `--source` is only needed for a local checkout:

```bash
./build-rocm.sh \
  --arch-env conf/amd-gfx1200.env \
  --rocm-env conf/amd-7.14.1.env \
  --llamacpp-env conf/llamacpp-v0.5.0.env \
  --config-env conf/build-config.env
```

```bash
./build-rocm.sh \
  --arch-env conf/amd-gfx1200.env \
  --rocm-env conf/amd-7.14.1.env \
  --llamacpp-env conf/llamacpp-v0.5.0.env \
  --config-env conf/build-config.env \
  --source /path/to/llama.cpp
```

To check how the arguments resolve without paying for a build, add `--dry-run`.
It prints the resolved `docker build` argument vector and exits without
invoking docker. `--no-cache` and `--verbose` are also supported; `--set
KEY=VALUE` (repeatable) overrides any resolved key.

### The resulting image

One build produces two tags. Deploy the versioned one: `latest` is overwritten
by the next build.

```
ghcr.io/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:1.1.0
ghcr.io/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:latest
```

The image runs `llama-server` on port 8080 by default (`LLAMA_ARG_HOST` /
`LLAMA_ARG_PORT`) with a `/health` healthcheck.

### Ports and the healthcheck

The listening port comes from the llama.cpp version configuration file: `conf/llamacpp-v0.5.0.env` sets `LLAMA_ARG_PORT=8080`, which `build-rocm.sh` passes to the build. The runtime stage derives its `LLAMA_ARG_PORT` environment from that value, and the healthcheck expands the same variable inside the container, so under the default and `-e LLAMA_ARG_PORT` overrides the probe cannot drift from the port the server reads; a `--port` CLI argument overrides the server only, and in that case the probe does drift (see below). The image keeps the official llama.cpp image's default: the internal port stays 8080, and you remap to a different host port rather than changing `--port`.

Docker CLI:

```bash
docker run -p 9090:8080 ghcr.io/agenticsnz/llama.cpp-...:latest \
  -m /models/model.gguf --host 0.0.0.0
```

Docker Compose:

```yaml
services:
  llama:
    image: ghcr.io/agenticsnz/llama.cpp-...:latest
    ports:
      - "9090:8080"
    command: >
      -m /models/model.gguf
      --host 0.0.0.0
```

If you must run the server on a different internal port, prefer setting `LLAMA_ARG_PORT`, for example `-e LLAMA_ARG_PORT=9090`: the healthcheck expands the same variable, so it follows the server without any custom configuration. A `--port` argument overrides the environment for the server only, leaving the healthcheck on the image's port; in that case override the healthcheck yourself, for example:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:9090/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

## Tests

Six suites, each in `tests/`. Run them from the repository root.

```bash
bash tests/test_build_args.sh
bash tests/test_build_stage.sh
bash tests/test_runtime_stage.sh
bash tests/test_issue_forms.sh
bash tests/test_contributing.sh
bash tests/test_docs.sh
```

`test_build_args.sh` verifies argument resolution through `--dry-run` — the
ownership, collision and warning rules — without invoking docker. It is fast
and needs no daemon.

`test_build_stage.sh` clones llama.cpp at the pinned tag, performs one real
build of the build stage, and asserts the HIP toolchain was found,
FlashAttention coverage is exactly the 49 combinations of the seven supported
K/V types, both artefacts exist, and the library closure resolves. It takes
several minutes and caches the checkout under `.tmp/`.

`test_runtime_stage.sh` builds the runtime stage and verifies the image is
self-contained: the loader resolves every library, the GPU is reported at run
time, and trimming removed other architectures' kernels without removing this
one's. It needs an AMD GPU visible to the docker daemon.

An image missing its ROCm libraries still starts, still reports the GPU through
`amd-smi`, and still passes a naive healthcheck — while exposing no compute
device at all. `llama-server --list-devices` is the check that distinguishes
those two images, and it is why the runtime suite refuses to skip when no GPU
is present.

`test_issue_forms.sh` verifies the six issue forms in `.github/ISSUE_TEMPLATE/`: chooser-valid front matter, the mandated required fields, the free-text axes and runtime fields, the log file uploads, and each add-support form's gate acknowledgement. It parses the forms' fixed YAML layout with grep and awk and needs no network or docker.

`test_contributing.sh` checks CONTRIBUTING.md for every mandated policy phrase: the labels, the branch naming standard, the issue-before-PR gate, the new-axes process, and the versioning conditions.

`test_docs.sh` checks the documentation split: the build sections live only in this guide, README and CONTRIBUTING link here, and this Tests section lists every suite.