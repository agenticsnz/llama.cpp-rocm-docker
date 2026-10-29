# llama.cpp-rocm-docker

A slim, single-architecture, HIP-targeted container image of
[llama.cpp](https://github.com/ggml-org/llama.cpp) for AMD ROCm.

It compiles `llama-server` (plus the `llama` CLI and backend libraries) for one
GPU architecture against one ROCm release, then ships a trimmed runtime: Ubuntu
24.04 plus the built binaries and only the ROCm libraries and kernel blobs that
architecture needs. The ~28 GB ROCm development base used to compile is
discarded; the published image is around 2.7 GB.

It is a drop-in replacement for the official llama.cpp image and functions
identically: the same `llama-server` entrypoint, flags, environment variables,
and HTTP API, built from the same upstream source at the pinned tag — only
the HIP backend is compiled for one architecture instead of many.

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

## Building locally

Prerequisites, the build procedure, the resulting image and the test
suites are covered in the [local build guide](docs/local-build-guide.md).

## Contributing

Bug reports, feature requests and add-support requests go through the issue
forms; the full workflow — labels, branch naming, new build targets,
versioning — is documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

## Authors

AgenticsNZ and Ciara Norrish (@Minouris).

