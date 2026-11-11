# Project Release Manifest: File, yq Access and Helper Tool — Design

**Issue:** #19 (Add project-release.yaml with project-version as the release source)
**Branch:** `enhancement/issue-19-project-release-yaml-source`
**Date:** 2026-11-11

## Intent

Issue #19 asks for one file that states the project's release state, so that the release pipelines and the test harness (#18) read the same values. This design covers the file, its shape, a helper script that reads and writes it, and the `yq` behaviour the script depends on. Features that act on the values (taking the image tag from `release_version`, checking `support` against `conf/`) come later.

## Goals

- A manifest file at `build-conf/project-release.yaml` with a top-level `release_version` key and a top-level `support` key.
- `support` holds three lists, one per axis: `llama-cpp`, `amd-rocm` and `amd-arch`. Each entry is the stem of an env file in `conf/`, so `llamacpp-v0.5.0` names `conf/llamacpp-v0.5.0.env`.
- A helper script, `scripts/release_manifest_tool.sh`, that reads and writes the manifest without being given its path.
- `yq` (v4.54.1, pinned in the devcontainer images) does the reading and writing.

## Non-goals

- `build-rocm.sh` does not read the manifest. Taking the image tag from `release_version` is a later feature.
- `VERSION` is not removed from `conf/build-config.env` here. That is a later feature.
- No test checks that the `support` stems match files in `conf/`, beyond the existence check that `--add` performs. The full check is a later feature.
- The env files do not move. They stay in `conf/` (option B below).

## Anti-goals

- The manifest must not become a second copy of axis values. The `support` lists name files; they do not repeat what the files say.

## Constraints

- The workspace repository is `agenticsnz/llama.cpp-rocm-docker`, and the build script and tests use `conf/`.
- `yq` v4 is the reader and writer. Ubuntu's `yq` package is a different tool and is not used (see `.devcontainer/Dockerfile.plain`).
- GitHub's hosted Ubuntu images list `yq 4.54.1` in their installed tools ([Ubuntu 24.04 readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), [Ubuntu 26.04 readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md), "Tools" section). These docs do not name the `yq` implementation.
- `yq` syntax follows the upstream README, [mikefarah/yq v4.54.1, "Basic Operations"](https://github.com/mikefarah/yq/blob/v4.54.1/README.md): `yq '<expr>' file` reads, and `yq -i '<expr>' file` updates in place. The operators used here (`+=`, `del`, `contains`, `keys`, `tag`) were checked against v4.54.1 in this design's verification.

## Approaches

1. **Flat bash-parsed file.** The script parses `key=value` lines itself, so there is no new dependency. Rejected: it is not YAML, and the file is meant to be read by the release pipelines and by the test harness.
2. **YAML read and write with `yq` v4 (chosen).** Standard YAML, read the same way on the devcontainer and on GitHub's runners. The cost is a pinned binary in the devcontainer images, which is already committed (`e91b742`).
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

- `release_version` is always double-quoted. An unquoted value such as `1.2` is read as a number (see R6), and the quotes keep it a string.
- Each `support` entry is a stem. The manifest holds no directory: the script's `CONF_DIR` constant supplies `conf/`, so `conf/` is never written into the manifest.

### The helper script

`scripts/release_manifest_tool.sh` finds the manifest relative to its own location, so it works from any working directory and takes no path argument.

```
release_manifest_tool.sh --get release_version
release_manifest_tool.sh --set release_version <value>
release_manifest_tool.sh --list <axis>
release_manifest_tool.sh --add <axis> <value>
release_manifest_tool.sh --delete <axis> <value>
```

- `<axis>` is one of `llama-cpp`, `amd-rocm`, `amd-arch`. Any other name is a usage error.
- `--get` and `--set` act only on `release_version`.
- `--list`, `--add` and `--delete` act only on an axis list.
- Exit status: `0` on success, `1` when a check fails and the manifest is unchanged, `2` for a usage error.

Skeleton (structure only; the bodies are stubs for the builder):

```bash
#!/usr/bin/env bash
# Reads and writes build-conf/project-release.yaml with yq v4.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MANIFEST="$REPO_ROOT/build-conf/project-release.yaml"
readonly CONF_DIR="$REPO_ROOT/conf"
readonly AXES="llama-cpp amd-rocm amd-arch"

usage() {
    cat <<'EOF'
Usage:
  release_manifest_tool.sh --get release_version
  release_manifest_tool.sh --set release_version <value>
  release_manifest_tool.sh --list <axis>
  release_manifest_tool.sh --add <axis> <value>
  release_manifest_tool.sh --delete <axis> <value>
EOF
}

usage_error() {
    echo "$1" >&2
    usage >&2
    exit 2
}

check_failed() {
    echo "$1" >&2
    exit 1
}

is_axis() {
    # Returns 0 when $1 is one of $AXES.
    return 1
}

is_valid_release_version() {
    # Returns 0 when $1 matches MAJOR.MINOR.PATCH with digits only.
    return 1
}

read_release_version() {
    # yq -r '.release_version' "$MANIFEST"
    return 1
}

write_release_version() {
    # yq -i '.release_version = "<value>"' "$MANIFEST"
    return 1
}

list_axis_values() {
    # yq -r '.support.<axis>[]' "$MANIFEST"
    return 1
}

add_axis_value() {
    # Checks: value not already in the list; "$CONF_DIR/<value>.env" exists.
    # yq -i '.support.<axis> += ["<value>"]' "$MANIFEST"
    return 1
}

delete_axis_value() {
    # Checks: value is in the list.
    # yq -i '.support.<axis> |= del(.[] | select(. == "<value>"))' "$MANIFEST"
    return 1
}

main() {
    case "${1:-}" in
        --get)    [ "$#" -eq 2 ] && [ "$2" = release_version ] || usage_error "--get takes release_version"
                  read_release_version ;;
        --set)    [ "$#" -eq 3 ] && [ "$2" = release_version ] || usage_error "--set takes release_version and a value"
                  write_release_version "$3" ;;
        --list)   [ "$#" -eq 2 ] || usage_error "--list takes one argument"
                  list_axis_values "$2" ;;
        --add)    [ "$#" -eq 3 ] || usage_error "--add takes two arguments"
                  add_axis_value "$2" "$3" ;;
        --delete) [ "$#" -eq 3 ] || usage_error "--delete takes two arguments"
                  delete_axis_value "$2" "$3" ;;
        *)        usage_error "missing or unknown command" ;;
    esac
}

main "$@"
```

### Requirements and scenarios

Each requirement is followed by the Gherkin scenarios that prove it. Each scenario is one outcome and maps to one test. The `yq` commands were checked against v4.54.1.

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

#### R6. Failure behaviour of the yq read and write paths

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

#### R7. The helper script reads and sets release_version

**Requirement:** `--get release_version` prints the stored version, and `--set release_version` replaces it only when the new value has the form `MAJOR.MINOR.PATCH` with digits.

**Scenario: Getting release_version works from another working directory**

```gherkin
Scenario: Getting release_version works from another working directory
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  And the working directory is /tmp
  When scripts/release_manifest_tool.sh --get release_version is run with the repository path
  Then stdout is exactly "1.2.0"
  And the exit status is 0
```

**Scenario: Setting release_version replaces the stored version**

```gherkin
Scenario: Setting release_version replaces the stored version
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When scripts/release_manifest_tool.sh --set release_version 1.3.0 is run
  Then the file contains the line release_version: "1.3.0"
  And the exit status is 0
```

**Scenario: Setting release_version rejects a value that is not MAJOR.MINOR.PATCH**

```gherkin
Scenario: Setting release_version rejects a value that is not MAJOR.MINOR.PATCH
  Given build-conf/project-release.yaml contains release_version: "1.2.0"
  When scripts/release_manifest_tool.sh --set release_version 1.3 is run
  Then the exit status is 1
  And the file still contains release_version: "1.2.0"
```

#### R8. The helper script lists an axis

**Requirement:** `--list <axis>` prints each value of that axis, one per line, in file order.

**Scenario: Listing amd-rocm prints its values in file order**

```gherkin
Scenario: Listing amd-rocm prints its values in file order
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0]
  When scripts/release_manifest_tool.sh --list amd-rocm is run
  Then stdout is "amd-7.14.1" followed by "amd-10.1.0", one per line
  And the exit status is 0
```

**Scenario: Listing an unknown top-level name is a usage error**

```gherkin
Scenario: Listing an unknown top-level name is a usage error
  Given build-conf/project-release.yaml exists
  When scripts/release_manifest_tool.sh --list gpu is run
  Then the exit status is 2
  And stderr contains the usage text
```

#### R9. The helper script adds a value to an axis

**Requirement:** `--add <axis> <value>` appends the value to that axis list when it is not already present and `conf/<value>.env` exists.

**Scenario: Adding a new value appends it to the axis list**

```gherkin
Scenario: Adding a new value appends it to the axis list
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0]
  And conf/amd-8.0.0.env exists
  When scripts/release_manifest_tool.sh --add amd-rocm amd-8.0.0 is run
  Then the amd-rocm list is [amd-7.14.1, amd-10.1.0, amd-8.0.0]
  And the exit status is 0
```

**Scenario: Adding a value already in the axis list is rejected**

```gherkin
Scenario: Adding a value already in the axis list is rejected
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0]
  When scripts/release_manifest_tool.sh --add amd-rocm amd-10.1.0 is run
  Then the exit status is 1
  And the amd-rocm list is unchanged
```

**Scenario: Adding a value with no matching env file is rejected**

```gherkin
Scenario: Adding a value with no matching env file is rejected
  Given build-conf/project-release.yaml contains amd-arch: [amd-gfx1200]
  And conf/amd-gfx9999.env does not exist
  When scripts/release_manifest_tool.sh --add amd-arch amd-gfx9999 is run
  Then the exit status is 1
  And the amd-arch list is unchanged
```

#### R10. The helper script deletes one value from an axis

**Requirement:** `--delete <axis> <value>` removes that value from the axis list and leaves the other values in place. It fails when the value is not in the list.

**Scenario: Deleting a value removes that value from the axis list**

```gherkin
Scenario: Deleting a value removes that value from the axis list
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0]
  When scripts/release_manifest_tool.sh --delete amd-rocm amd-10.1.0 is run
  Then the amd-rocm list is [amd-7.14.1]
  And the exit status is 0
```

**Scenario: Deleting a value leaves the other axis lists unchanged**

```gherkin
Scenario: Deleting a value leaves the other axis lists unchanged
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0] and amd-arch: [amd-gfx1200]
  When scripts/release_manifest_tool.sh --delete amd-rocm amd-10.1.0 is run
  Then the amd-arch list is [amd-gfx1200]
```

**Scenario: Deleting a value not in the axis list is rejected**

```gherkin
Scenario: Deleting a value not in the axis list is rejected
  Given build-conf/project-release.yaml contains amd-rocm: [amd-7.14.1, amd-10.1.0]
  When scripts/release_manifest_tool.sh --delete amd-rocm amd-9.9.9 is run
  Then the exit status is 1
  And the amd-rocm list is unchanged
```

#### R11. The helper script rejects missing or unknown arguments

**Requirement:** With no command, an unknown command, or an axis name that is not one of the three, the script prints usage and exits with status 2 without touching the file.

**Scenario: Getting an axis name as release_version is a usage error**

```gherkin
Scenario: Getting an axis name as release_version is a usage error
  Given build-conf/project-release.yaml exists
  When scripts/release_manifest_tool.sh --get amd-rocm is run
  Then the exit status is 2
  And stderr contains the usage text
```

**Scenario: Running with no command is a usage error**

```gherkin
Scenario: Running with no command is a usage error
  Given build-conf/project-release.yaml exists
  When scripts/release_manifest_tool.sh is run with no arguments
  Then the exit status is 2
  And stderr contains the usage text
```

**Scenario: Adding to an unknown axis is a usage error**

```gherkin
Scenario: Adding to an unknown axis is a usage error
  Given build-conf/project-release.yaml exists
  When scripts/release_manifest_tool.sh --add gpu gfx1200 is run
  Then the exit status is 2
  And the file is unchanged
```

## What is left to the builder

- The exact `yq` invocation in each function, beyond the expressions above.
- The scenarios that touch the file run against a copy of the tree (`scripts/`, `build-conf/`, `conf/`) in `.tmp/`, so the committed manifest is never changed by a test. The script resolves the manifest relative to its own location, so the copy needs no path override.
- The `conf/<value>.env` existence check in `--add` uses `CONF_DIR`, which resolves to the copy's `conf/` directory.

## Calls I made

- **File location:** `build-conf/project-release.yaml`, using the name from issue #19.
- **Key names:** `release_version` and `support`, as you specified. Issue #19 uses `project-version`; this design follows your spec.
- **Quoting:** `release_version` is always double-quoted, because of the float behaviour in R6.
- **Env files stay in `conf/`:** option B from our discussion.
- **Parser:** `yq` v4 (option 2 above).
- **Addressing:** `--get` and `--set` act on `release_version`; `--list`, `--add` and `--delete` act on an axis. You specified this.
- **Version format:** `--set` accepts `MAJOR.MINOR.PATCH` with digits only. This is my choice; the issue does not state a format.
- **`--add` checks:** the value must not already be listed, and `conf/<value>.env` must exist. The second check is my choice, so that the list cannot name a missing file.
- **Exit codes:** `0` success, `1` check failed with the file unchanged, `2` usage error. This is my choice.
- **`conf/` as a constant:** the script defines `CONF_DIR` once, and the manifest holds only axis stems. This follows your instruction.
