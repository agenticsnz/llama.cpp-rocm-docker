# Image Version Read From the Release Manifest — Design

**Issue:** #14 (Make the image version number truly independent of build-config.env)
**Branch:** `enhancement/issue-14-make-image-version-independent`
**Date:** 2026-11-12

## Intent

The image version is `VERSION` in `conf/build-config.env`, which is also where the axis-neutral settings live. Issue #14 asks for it to have its own source. The release manifest from #19 already holds `release_version`, so this change makes `build-rocm.sh` read that key and removes `VERSION` from the build config. There is then one version source.

## Goals

- `build-rocm.sh` takes the image tag version from `release_version` in `build-conf/project-release.yaml`.
- The script reads that value through `scripts/release_manifest_tool.sh --get release_version`.
- `VERSION` is removed from `conf/build-config.env`.

## Non-goals

- No change to image contents. The Dockerfile never declares `ARG VERSION`.
- No version bump. The value stays `1.2.0`.
- No change to the ROCm, GPU or llama.cpp axes.
- No per-build version override.

## Anti-goals

- A second version source. Nothing may read the version from `conf/build-config.env`, from a `--set` argument, or from a shell variable.

## Constraints

- The manifest tool needs `yq` v4 on `PATH`. The devcontainers install it (`e91b742`), and GitHub's hosted Ubuntu images list it (see the spec for #19).
- `--set` accepts any key, so without a rule a `--set VERSION=...` would be ignored silently.
- `docker build` warns about an unknown `--build-arg` and carries on, so removing `VERSION` from the build arguments has no effect on the image.

## Approaches

1. **Read the manifest with the tool (chosen).** One source, and the reader already exists and is tested. Cost: `build-rocm.sh` depends on `yq`.
2. **A plain version file.** No new tool, but a second version source beside `release_version`.
3. **A dedicated axis file with a new flag.** Fits the axis pattern, but adds a required flag and the version is not an axis.

## Design

### Reading the version

`build-rocm.sh` runs `"$SCRIPT_DIR/scripts/release_manifest_tool.sh" --get release_version` once, during argument resolution, and stores the result in `IMAGE_VERSION`. The script checks the result against `MAJOR.MINOR.PATCH` digits, the same rule the tool applies to `--set`. A failed read or a failed check stops the build with a message that names `build-conf/project-release.yaml`.

### Where the version is used

- The version tag, `<reference>:<IMAGE_VERSION>`, is emitted in both the dry-run output and the real build.
- The `latest` tag is unchanged.
- `VERSION` is removed from `KEY_AXIS`, from `REQUIRED_KEYS`, and from the `--build-arg` list.

### Overrides

`--set VERSION=<value>` is rejected, with a message that names `build-conf/project-release.yaml`. The message tells the user to change `release_version` in the manifest instead.

### Documentation

`CONTRIBUTING.md` (the "Versioning" paragraph) and `README.md` (the neutral-axis table) name the manifest as the source.

## Requirements and scenarios

#### R1. The image tag uses release_version from the manifest

**Requirement:** The version tag comes from `release_version` in `build-conf/project-release.yaml`.

**Scenario: A dry run tags the image with the manifest version**

```gherkin
Scenario: A dry run tags the image with the manifest version
  Given build-conf/project-release.yaml has release_version "1.2.0"
  When build-rocm.sh is run with --dry-run and the existing axis files
  Then the output contains "--tag ghcr.io/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:1.2.0"
```

**Scenario: A changed manifest version changes the tag**

```gherkin
Scenario: A changed manifest version changes the tag
  Given a copy of the tree whose build-conf/project-release.yaml has release_version "1.3.0"
  When build-rocm.sh is run with --dry-run from that copy
  Then the output contains "--tag ghcr.io/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:1.3.0"
```

#### R2. VERSION is no longer read from the build config

**Requirement:** `conf/build-config.env` does not declare `VERSION`, and a `VERSION` line in that file does not change the tag.

**Scenario: The build config file does not declare VERSION**

```gherkin
Scenario: The build config file does not declare VERSION
  Given conf/build-config.env exists
  When the file is searched for a line starting with VERSION=
  Then no line matches
```

**Scenario: A VERSION line in the build config does not change the tag**

```gherkin
Scenario: A VERSION line in the build config does not change the tag
  Given a copy of the tree whose conf/build-config.env has the line VERSION=9.9.9 appended
  And build-conf/project-release.yaml has release_version "1.2.0"
  When build-rocm.sh is run with --dry-run from that copy
  Then the output contains "--tag ghcr.io/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:1.2.0"
```

#### R3. VERSION is not passed as a build argument

**Requirement:** The dry-run build arguments carry no `VERSION`.

**Scenario: A dry run emits no VERSION build argument**

```gherkin
Scenario: A dry run emits no VERSION build argument
  Given the existing axis files and build-conf/project-release.yaml
  When build-rocm.sh is run with --dry-run
  Then the output contains no line starting with "--build-arg VERSION="
```

#### R4. A --set VERSION override is rejected

**Requirement:** `--set VERSION=...` fails, so the override cannot be silently ignored.

**Scenario: Overriding VERSION with --set exits non-zero**

```gherkin
Scenario: Overriding VERSION with --set exits non-zero
  Given the existing axis files and build-conf/project-release.yaml
  When build-rocm.sh is run with --set VERSION=9.9.9 and --dry-run
  Then the exit status is non-zero
```

**Scenario: Overriding VERSION with --set names the manifest in its error**

```gherkin
Scenario: Overriding VERSION with --set names the manifest in its error
  Given the existing axis files and build-conf/project-release.yaml
  When build-rocm.sh is run with --set VERSION=9.9.9 and --dry-run
  Then stderr names build-conf/project-release.yaml
```

#### R5. The manifest version must be readable and well-formed

**Requirement:** The build stops when `release_version` is missing, is not `MAJOR.MINOR.PATCH`, or the manifest is absent, and the error names the manifest.

**Scenario: A missing release_version exits non-zero**

```gherkin
Scenario: A missing release_version exits non-zero
  Given a copy of the tree whose build-conf/project-release.yaml has no release_version key
  When build-rocm.sh is run with --dry-run from that copy
  Then the exit status is non-zero
```

**Scenario: A missing release_version is named in the error**

```gherkin
Scenario: A missing release_version is named in the error
  Given a copy of the tree whose build-conf/project-release.yaml has no release_version key
  When build-rocm.sh is run with --dry-run from that copy
  Then stderr names build-conf/project-release.yaml
```

**Scenario: A malformed release_version exits non-zero**

```gherkin
Scenario: A malformed release_version exits non-zero
  Given a copy of the tree whose build-conf/project-release.yaml has release_version "1.2"
  When build-rocm.sh is run with --dry-run from that copy
  Then the exit status is non-zero
```

**Scenario: A malformed release_version is named in the error**

```gherkin
Scenario: A malformed release_version is named in the error
  Given a copy of the tree whose build-conf/project-release.yaml has release_version "1.2"
  When build-rocm.sh is run with --dry-run from that copy
  Then stderr names build-conf/project-release.yaml
```

**Scenario: A missing manifest exits non-zero**

```gherkin
Scenario: A missing manifest exits non-zero
  Given a copy of the tree with no build-conf/project-release.yaml
  When build-rocm.sh is run with --dry-run from that copy
  Then the exit status is non-zero
```

**Scenario: A missing manifest is named in the error**

```gherkin
Scenario: A missing manifest is named in the error
  Given a copy of the tree with no build-conf/project-release.yaml
  When build-rocm.sh is run with --dry-run from that copy
  Then stderr names build-conf/project-release.yaml
```

**Scenario: A missing yq exits non-zero**

```gherkin
Scenario: A missing yq exits non-zero
  Given yq is not on PATH
  When build-rocm.sh is run with --dry-run
  Then the exit status is non-zero
```

**Scenario: A missing yq is named in the error**

```gherkin
Scenario: A missing yq is named in the error
  Given yq is not on PATH
  When build-rocm.sh is run with --dry-run
  Then stderr names yq
```

#### R6. Documentation names the manifest as the version source

**Requirement:** `CONTRIBUTING.md` and `README.md` describe the manifest as the source of the image version.

**Scenario: CONTRIBUTING.md names the manifest in the Versioning section**

```gherkin
Scenario: CONTRIBUTING.md names the manifest in the Versioning section
  Given CONTRIBUTING.md
  When the Versioning section is searched for the phrase "build-conf/project-release.yaml"
  Then the phrase is found
```

**Scenario: The README neutral-axis table does not name VERSION**

```gherkin
Scenario: The README neutral-axis table does not name VERSION
  Given README.md
  When the neutral-axis table is read
  Then no row names VERSION as a key of conf/build-config.env
```

## What is left to the builder

- The exact `yq` call in `build-rocm.sh`, and where the manifest-reading step sits in the argument flow.
- The exact wording of the error messages, as long as each names the file or tool the scenarios require.
- Test changes in `tests/test_build_args.sh`: `EXPECTED_IMAGE_VERSION` is read from the manifest, the fixture lines `VERSION=1.1.1` and `VERSION=1.0.0` are removed, and each scenario above maps to one test.

## Calls I made

- **Override:** `--set VERSION=...` is rejected, not ignored, so a stale override can't survive unnoticed. The issue does not cover this; it follows from removing the key.
- **Build argument:** `VERSION` is dropped from the build arguments, since the Dockerfile never uses it.
- **Version format:** the script applies the same `MAJOR.MINOR.PATCH` check as the tool's `--set`.
- **Missing yq:** stops the build with a message, rather than falling back to another source.
- **Docs:** `CONTRIBUTING.md` and `README.md` are updated in the same change, so they don't name a location that no longer holds the value.
