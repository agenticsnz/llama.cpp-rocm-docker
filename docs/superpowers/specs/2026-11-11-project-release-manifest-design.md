# Project Release Manifest: File and yq Access — Design

**Issue:** #19 (Add project-release.yaml with project-version as the release source)
**Branch:** `enhancement/issue-19-project-release-yaml-source`
**Date:** 2026-11-11

## Intent

Issue #19 asks for one file that states the project's release state, so that the release pipelines and the test harness (#18) read the same values. This design covers the first step only: the file exists, it has the agreed shape, and `yq` can read and write its `release_version` string. Features that act on those values come later.

## Goals

- A manifest file at `build-conf/project-release.yaml` with a top-level `release_version` key and a top-level `support` key.
- `support` holds three lists, one per axis: `llama-cpp`, `amd-rocm` and `amd-arch`. Each entry is the stem of an env file in `conf/`, so `llamacpp-v0.5.0` names `conf/llamacpp-v0.5.0.env`.
- `yq` (v4.54.1, pinned in the devcontainer images) reads `release_version` and writes it back in place, keeping it a quoted string.

## Non-goals

- `build-rocm.sh` does not read the manifest. Taking the image tag from `release_version` is a later feature.
- `VERSION` is not removed from `conf/build-config.env` here. That is a later feature.
- No test checks that the `support` stems match files in `conf/`. That is a later feature.
- The env files do not move. They stay in `conf/` (option B below).

## Anti-goals

- The manifest must not become a second copy of axis values. The `support` lists name files; they do not repeat what the files say.

## Constraints

- The workspace repository is `agenticsnz/llama.cpp-rocm-docker`, and the build script and tests use `conf/`.
- `yq` v4 is the reader. Ubuntu's `yq` package is a different tool and is not used (see `.devcontainer/Dockerfile.plain`).
- GitHub's hosted Ubuntu images list `yq 4.54.1` in their installed tools ([Ubuntu 24.04 readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), [Ubuntu 26.04 readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md), "Tools" section). These docs do not name the `yq` implementation.
- `yq` read and write syntax follows the upstream README, [mikefarah/yq v4.54.1, "Basic Operations"](https://github.com/mikefarah/yq/blob/v4.54.1/README.md): `yq '<expr>' file` reads, and `yq -i '<expr>' file` updates in place.

## Approaches

1. **Flat bash-parsed file.** The script parses `key=value` lines itself, so there is no new dependency. Rejected: it is not YAML, and the file is meant to be read by the release pipelines and by the test harness.
2. **YAML read with `yq` v4 (chosen).** Standard YAML, read the same way on the devcontainer and on GitHub's runners. The cost is a pinned binary in the devcontainer images, which is already committed (`e91b742`).
3. **YAML read with `python3` and PyYAML.** Rejected: the devcontainer and the runners would both need the module installed, and it has not been checked.

## Design

### The file

`build-conf/project-release.yaml`:

```yaml
release_version: "1.2.0"
support:
  llama-cpp: [llamacpp-v0.5.0]
  amd-rocm: [amd-7.14.1, amd-10.1.0]
  amd-arch: [amd-gfx1200]
```

- `release_version` is always double-quoted. An unquoted value such as `1.2` is read as a number (see the failure scenario below), and the quotes keep it a string.
- Each `support` entry must match a file `conf/<entry>.env`. That check belongs to a later feature.

### Requirements and scenarios

Each requirement below is followed by the Gherkin scenarios that prove it. Each scenario is a single outcome and maps to one test. The commands are the ones checked against `yq` v4.54.1 in this design's verification.

#### R1. The manifest file exists at its path

**Requirement:** The file `build-conf/project-release.yaml` is present in the repository.

**Scenario: The manifest file exists at build-conf/project-release.yaml**

```gherkin
Scenario: The manifest file exists at build-conf/project-release.yaml
  Given the repository root is the working directory
  When the path build-conf/project-release.yaml is tested as a regular file
  Then the test succeeds
```

#### R2. yq reads release_version as its string value

**Requirement:** `yq` returns the exact version string stored under `release_version`.

**Scenario: Reading release_version returns the stored version**

```gherkin
Scenario: Reading release_version returns the stored version
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When yq -r '.release_version' is run on the file
  Then stdout is exactly "1.2.0"
  And the exit status is 0
```

**Scenario: Reading release_version reports a string type**

```gherkin
Scenario: Reading release_version reports a string type
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When yq -r '.release_version | tag' is run on the file
  Then stdout is exactly "!!str"
```

#### R3. yq writes release_version in place and keeps it quoted

**Requirement:** `yq -i` replaces the value and keeps the double quotes, so the file still reads as a string.

**Scenario: Writing release_version replaces the stored version**

```gherkin
Scenario: Writing release_version replaces the stored version
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When yq -i '.release_version = "1.3.0"' is run on the file
  And yq -r '.release_version' is run on the file
  Then stdout is exactly "1.3.0"
```

**Scenario: Writing release_version keeps the value double-quoted**

```gherkin
Scenario: Writing release_version keeps the value double-quoted
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When yq -i '.release_version = "1.3.0"' is run on the file
  Then the file contains the line release_version: "1.3.0"
```

**Scenario: Writing a numeric-looking release_version keeps it a string**

```gherkin
Scenario: Writing a numeric-looking release_version keeps it a string
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When yq -i '.release_version = "1.3"' is run on the file
  And yq -r '.release_version | tag' is run on the file
  Then stdout is exactly "!!str"
```

#### R4. The support key exposes the three axis lists

**Requirement:** `support` has exactly the three axis keys, and `yq` can list them.

**Scenario: Listing the support keys returns the three axes**

```gherkin
Scenario: Listing the support keys returns the three axes
  Given build-conf/project-release.yaml contains a support key with llama-cpp, amd-rocm and amd-arch lists
  When yq -o=json '.support | keys' is run on the file
  Then stdout is the JSON array ["llama-cpp", "amd-rocm", "amd-arch"] in that order
```

#### R5. yq is available in the devcontainer

**Requirement:** The devcontainer images provide `yq` v4.54.1, as committed in `e91b742`.

**Scenario: The devcontainer image reports yq v4.54.1**

```gherkin
Scenario: The devcontainer image reports yq v4.54.1
  Given the devcontainer image built from .devcontainer/Dockerfile.plain
  When yq --version is run in the image
  Then stdout contains "yq (https://github.com/mikefarah/yq/) version v4.54.1"
```

#### R6. Failure behaviour of the read and write paths

**Requirement:** The failure behaviour of `yq` on this file is stated, so later features do not assume otherwise.

**Scenario: Reading from a missing file fails**

```gherkin
Scenario: Reading from a missing file fails
  Given build-conf/project-release.yaml does not exist
  When yq -r '.release_version' is run on the file
  Then the exit status is 1
  And stderr contains "no such file or directory"
```

**Scenario: Writing to a missing file fails**

```gherkin
Scenario: Writing to a missing file fails
  Given build-conf/project-release.yaml does not exist
  When yq -i '.release_version = "1.3.0"' is run on the file
  Then the exit status is 1
  And the file is not created
```

**Scenario: Reading a missing release_version key returns null without failing**

```gherkin
Scenario: Reading a missing release_version key returns null without failing
  Given build-conf/project-release.yaml contains only the key other: 1
  When yq -r '.release_version' is run on the file
  Then stdout is exactly "null"
  And the exit status is 0
```

**Scenario: An unquoted numeric release_version reads as a float**

```gherkin
Scenario: An unquoted numeric release_version reads as a float
  Given build-conf/project-release.yaml contains release_version: 1.2
  When yq -r '.release_version | tag' is run on the file
  Then stdout is exactly "!!float"
```

## What is left to the builder

- The exact `yq` invocation in the test script, beyond the expressions above.
- Whether the tests use a temporary copy of the file or the real file for the write scenarios. Use a copy, so the committed manifest is never changed by a test.
- The temporary directory for those copies: `.tmp/`, as AGENTS.md requires.

## Calls I made

- **File location:** `build-conf/project-release.yaml`, using the name from issue #19.
- **Key names:** `release_version` and `support`, as you specified. Issue #19 uses `project-version`; this design follows your spec.
- **Quoting:** `release_version` is always double-quoted, because of the float behaviour shown in R6.
- **Env files stay in `conf/`:** option B from our discussion.
- **Parser:** `yq` v4 (option 2 above).
