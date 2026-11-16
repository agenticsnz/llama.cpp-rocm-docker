# Issue 16: Ship amd-smi and rocm-smi in the runtime image - Design

**Date:** 2026-11-16
**Issue:** #16
**Branch:** `enhancement/issue-16-ship-amd-smi-in-image`
**Milestone:** release-1.2.0

---

## Problem

The runtime image built by `Dockerfile.rocm` does not contain `amd-smi`. The healthcheck and the device report expect it. The runtime stage (`FROM ubuntu:24.04 AS runtime`, lines 248–255) installs only `libgomp1 curl ffmpeg ca-certificates`, and the runtime tree copy (lines 221–238) takes only the resolved library closure plus files whose names contain the GPU token. Neither SMI tool is a library, so the current copy rules never bring it in. Python, which both tools need, is also absent.

## Discovery (per ROCm axis)

Each ROCm axis names its SMI packages differently. The following was read from the published bases with `dpkg-query` and `dpkg -L` on 2026-11-16.

| | 7.14.1 base (`rocm/dev-ubuntu-24.04:7.14.1-full`) | 10.1.0 base (`rocm/dev-ubuntu-24.04:10.1.0-full`) |
|---|---|---|
| `amd-smi` package | `amdrocm-amdsmi7.14` 7.14.1-0 | `amdrocm-amdsmi10.1` 10.1.0-3 |
| `amd-smi` path | `/opt/rocm/core-7.14/bin/amd-smi` | `/opt/rocm/core-10.1/bin/amd-smi` |
| `rocm-smi` package | `amdrocm-base7.14` 7.14.1-0 | none |
| `rocm-smi` path | `/opt/rocm/core-7.14/bin/rocm-smi` | not present |
| `amd-smi` depends on | `libc6`, `python3` (>= 3.6.8), `amdrocm-sysdeps7.14` | `libc6`, `python3` (>= 3.6.8), `amdrocm-sysdeps10.1` |
| `rocm-smi` depends on | `libgcc-s1`, `libstdc++6`, `python3`, `libc6`, `amdrocm-runtime7.14` | — |
| Python in base | 3.12.3 | 3.12.3 |

Installed sizes: `amdrocm-amdsmi7.14` 36.5 MB, `amdrocm-sysdeps7.14` 61.8 MB, `amdrocm-base7.14` 5.3 MB, `amdrocm-runtime7.14` 48.3 MB (its dependency `amdrocm-llvm7.14` is not measured), `amdrocm-amdsmi10.1` 31.3 MB, `amdrocm-sysdeps10.1` 61.8 MB.

Both `amd-smi` entry points are Python scripts (`#!/usr/bin/env python3`) that the base installs under the core tree. `/usr/bin/amd-smi` and `/usr/bin/rocm-smi` point there through `/etc/alternatives`.

Method for each future axis: repeat this discovery against the axis's base before writing its axis file.

## Approach

**Axis files carry package names and nothing else.** Each ROCm axis file gets the package names for its SMI tools. An empty value means the tool is absent on that axis:

```
AMD_SMI_PACKAGE=amdrocm-amdsmi7.14
ROCM_SMI_PACKAGE=amdrocm-base7.14
```

On 10.1.0, `ROCM_SMI_PACKAGE` is empty.

**`Dockerfile.rocm` does the work.** It declares the package ARGs, installs the named packages in the build stage, and copies the core tree's SMI files into the runtime stage. Keys that the axis files set must have a matching `ARG`, which `build-rocm.sh` already checks (lines 267–291).

**No shell snippets in axis files.** Logic that cannot be expressed as data goes in a script under the repo, copied in by the Dockerfile. The axis file names the script with a key.

**Flavours are out of scope.** `-profile` and `-debug` images will be extra Docker build stages on top of `runtime`, selected with `--target` (Docker multi-stage builds, "Stop at a specific build stage"). That work is tracked in separate tickets. This design keeps all version-specific logic upstream of `runtime` so that any future flavour inherits it.

## R1: amd-smi is available on PATH in the runtime image

Scenario: amd-smi version prints the library version on the 7.14.1 axis

```gherkin
Scenario: amd-smi version prints the library version on the 7.14.1 axis
  Given the runtime image is built for the amd-7.14.1 axis
  When the image runs "amd-smi version"
  Then the output contains an "AMDSMI Library version" line
```

Scenario: amd-smi version prints the library version on the 10.1.0 axis

```gherkin
Scenario: amd-smi version prints the library version on the 10.1.0 axis
  Given the runtime image is built for the amd-10.1.0 axis
  When the image runs "amd-smi version"
  Then the output contains an "AMDSMI Library version" line
```

Scenario: the build fails when the amd-smi package is not provided by the base

```gherkin
Scenario: the build fails when the amd-smi package is not provided by the base
  Given an axis file sets AMD_SMI_PACKAGE to a package name the base does not provide
  When the image is built
  Then the build fails before the runtime stage is produced
```

## R2: rocm-smi is available on PATH where its axis provides it

Scenario: rocm-smi --version runs on the 7.14.1 axis

```gherkin
Scenario: rocm-smi --version runs on the 7.14.1 axis
  Given the runtime image is built for the amd-7.14.1 axis
  When the image runs "rocm-smi --version"
  Then the command exits with status 0
```

Scenario: the 10.1.0 axis builds when ROCM_SMI_PACKAGE is empty

```gherkin
Scenario: the 10.1.0 axis builds when ROCM_SMI_PACKAGE is empty
  Given the runtime image is built for the amd-10.1.0 axis with ROCM_SMI_PACKAGE empty
  When the image is built
  Then the build succeeds
```

Scenario: rocm-smi is not on PATH when ROCM_SMI_PACKAGE is empty

```gherkin
Scenario: rocm-smi is not on PATH when ROCM_SMI_PACKAGE is empty
  Given the runtime image is built for the amd-10.1.0 axis with ROCM_SMI_PACKAGE empty
  When the image runs "command -v rocm-smi"
  Then the command exits with a non-zero status
```

Scenario: the build fails when ROCM_SMI_PACKAGE names a package the base does not provide

```gherkin
Scenario: the build fails when ROCM_SMI_PACKAGE names a package the base does not provide
  Given an axis file sets ROCM_SMI_PACKAGE to a package name the base does not provide
  When the image is built
  Then the build fails before the runtime stage is produced
```

## R3: the python dependencies of the SMI tools are satisfied at runtime

Scenario: python3 runs in the 7.14.1 runtime image

```gherkin
Scenario: python3 runs in the 7.14.1 runtime image
  Given the runtime image is built for the amd-7.14.1 axis
  When the image runs "python3 --version"
  Then the command exits with status 0
```

Scenario: python3 runs in the 10.1.0 runtime image

```gherkin
Scenario: python3 runs in the 10.1.0 runtime image
  Given the runtime image is built for the amd-10.1.0 axis
  When the image runs "python3 --version"
  Then the command exits with status 0
```

## R4: package names come from the axis files

Scenario: the installed amd-smi package matches AMD_SMI_PACKAGE

```gherkin
Scenario: the installed amd-smi package matches AMD_SMI_PACKAGE
  Given the amd-7.14.1 axis file sets AMD_SMI_PACKAGE to "amdrocm-amdsmi7.14"
  When the runtime image is built
  Then the dpkg status of the image lists "amdrocm-amdsmi7.14" as installed
```

## R5: discovery is repeated for every axis

Scenario: an axis file without AMD_SMI_PACKAGE is rejected

```gherkin
Scenario: an axis file without AMD_SMI_PACKAGE is rejected
  Given a ROCm axis file that omits the AMD_SMI_PACKAGE key
  When the axis is checked for the release
  Then the check fails and names AMD_SMI_PACKAGE as missing
```

Scenario: an axis file without ROCM_SMI_PACKAGE is rejected

```gherkin
Scenario: an axis file without ROCM_SMI_PACKAGE is rejected
  Given a ROCm axis file that omits the ROCM_SMI_PACKAGE key
  When the axis is checked for the release
  Then the check fails and names ROCM_SMI_PACKAGE as missing
```

---

## Open items

- `rocm-smi` is absent on 10.1.0. The design treats it as optional per axis, so 10.1.0 builds without it and the image documentation says so.
- `amdrocm-llvm7.14` has not been measured, so the 7.14.1 dependency size is a lower bound.
- The 10.1.0 path for `amd-smi` has not been exercised in a built image, only inspected in the base.
- The python dependency set in the runtime image is not decided. The design requires it to be satisfied; how is part of the implementation plan.

## Out of scope

- Flavour images (`-profile`, `-debug`) and their tags
- Changes to the healthcheck beyond what amd-smi availability requires
