# llama.cpp-rocm-docker

A slim, single-architecture, HIP-targeted container image of
[llama.cpp](https://github.com/ggml-org/llama.cpp) for AMD ROCm.

It compiles `llama-server` (plus the `llama` CLI and backend libraries) for one
GPU architecture against one ROCm release, then ships a trimmed runtime: Ubuntu
24.04 plus the built binaries and only the ROCm libraries and kernel blobs that
architecture needs. The ~28 GB ROCm development base used to compile is
discarded; the published image is around 2.7 GB.

Retargeting to another card or ROCm release means adding files under `conf/`,
not editing the script or Dockerfile.

## Build config files

`build-rocm.sh` is driven by three configuration files, each owning one axis of
the build. Nothing about the image is hard-coded in the script or in
`Dockerfile.rocm`.

| File | Owns |
|---|---|
| `conf/amd-gfx1200.env` | Anything that changes with the GPU card |
| `conf/amd-7.14.1.env`, `conf/amd-10.1.0.env` | Anything that changes with the ROCm release |
| `conf/build-config.env` | Everything else (build type, versions, registry) |

A key appearing in more than one file resolves to whichever file owns that
axis. The other copy is reported and discarded.

### Architectures

| File | Build argument | GPU target |
|---|---|---|
| `conf/amd-gfx1200.env` | `--arch-env` | `gfx1200` |

| Variable | Used for |
|---|---|
| `GPU_TARGET` | LLVM / `AMDGPU_TARGETS` value passed to CMake and HIP; also selects which kernel blobs are kept in the runtime tree |
| `ARCH_STRING` | Name fragment for the image tag. It is usually the same as `GPU_TARGET`, but one arch file may compile for several targets under a single shared label, e.g. `GPU_TARGET=gfx1200;gfx1201` with `ARCH_STRING=RDNA4` |
| `GGML_CUDA_FA_QUANTS` | FlashAttention K/V type combinations compiled in (`all` = full 49-combination cross-product of the seven supported types) |

### ROCm releases

| File | Build argument | ROCm version |
|---|---|---|
| `conf/amd-7.14.1.env` | `--rocm-env` | `7.14.1` |
| `conf/amd-10.1.0.env` | `--rocm-env` | `10.1.0` |

| Variable | Used for |
|---|---|
| `ROCM_BASE` | Development base image the build stage compiles in |
| `ROCM_VERSION` | ROCm release number; part of the image tag |
| `ROCM_BASE_ASSEMBLY` | Records how the base was sourced (`published-multiarch-image`); informational, carried in build history |
| `ROCM_CORE_DIR` | Version-scoped install root inside the base (e.g. `/opt/rocm/core-7.14`); source tree for the trimmed runtime copy |
| `LD_LIBRARY_PATH` | Runtime library path the base image does not register via `ld.so.conf`; without it `libggml-hip.so` cannot resolve `libamdhip64` |

### Neutral axis (`conf/build-config.env`)

| Variable | Used for |
|---|---|
| `CMAKE_BUILD_TYPE` | CMake build type (`Release`) |
| `REGISTRY` | Registry host for the image reference (no scheme, no trailing slash) |
| `LLAMA_CPP_VERSION` | llama.cpp tag the source checkout must be at; part of the image tag |
| `VERSION` | Image version tag published alongside `latest` |
| `GGML_NATIVE` | `OFF`, so the CPU backend is not tuned to the build host |

## Prerequisites

- Docker with Compose v2
- The **AMD Container Toolkit**, so `docker` exposes the GPU
- An amdgpu host driver on 30.x or 31.x (ROCm release numbers and amdgpu
  driver numbers are separate schemes)
- A llama.cpp source checkout at the tag named by `LLAMA_CPP_VERSION`. This is
  a path outside this repository — the build copies that whole tree as its
  build context.

## Building

All three configuration files are required. The script rejects a partial
invocation rather than guessing which axis was meant:

```bash
./build-rocm.sh \
  --arch-env conf/amd-gfx1200.env \
  --rocm-env conf/amd-7.14.1.env \
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

## Tests

Three suites, each in `tests/`. Run them from the repository root.

```bash
bash tests/test_build_args.sh
bash tests/test_build_stage.sh
bash tests/test_runtime_stage.sh
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

## License

MIT — see [LICENSE](LICENSE).

## Authors

AgenticsNZ and Ciara Norrish (@Minouris).

