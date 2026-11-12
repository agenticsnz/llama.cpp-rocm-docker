# Image Version From the Release Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `build-rocm.sh` takes the image tag from `release_version` in `build-conf/project-release.yaml`, appends `-dev` when `is_dev` is true, and no longer reads `VERSION` from `conf/build-config.env`.

**Architecture:** The manifest tool gains a generic `--get <key>` (tool design R12). The build script reads `release_version` and `is_dev` through that tool, validates both, and builds the tag from them. `VERSION` leaves the build config's key tables, so no config file or shell variable can set it.

**Tech Stack:** bash, `yq` v4.54.1 (on `PATH` in the devcontainers and on GitHub's runners), shellcheck.

**Spec:** `docs/superpowers/specs/2026-11-12-image-version-from-manifest-design.md` (R1 to R9, with the tool change in `docs/superpowers/specs/2026-11-11-project-release-manifest-design.md`, R12). Every scenario named below is in the spec; its title is the test name.

## Global Constraints

- `release_version` must match `^[0-9]+\.[0-9]+\.[0-9]+$`. Checked by the build script, after the tool returns it.
- `is_dev` must be exactly `true` or `false`. Checked by the build script. `True`, `yes` and `1` are rejected.
- Tag format: `<reference>:<release_version>` when `is_dev` is `false`, `<reference>:<release_version>-dev` when `true`. `latest` is published only when `is_dev` is `false`.
- The build script's `die` exits with status 2. The tool's check failures exit with status 1 and its usage errors with status 2.
- Tests never change the committed `build-conf/project-release.yaml`, `conf/` or any tracked file. Build tests that need a different manifest copy the tree (`build-rocm.sh`, `scripts/`, `build-conf/`, `conf/`) into `.tmp/` and edit the copy.
- Commit messages are imperative, under 72 characters, with no co-author lines.

## Review Focus

- A `VERSION` line in a config file is ignored with a warning and never becomes a build argument. Expected: tag from the manifest, no `--build-arg VERSION`. Test in Task 3.
- An exported shell variable `VERSION` is ignored. Expected: tag from the manifest. Test in Task 3.
- `is_dev: True` (capitalised) is rejected. Expected: non-zero exit, error names the manifest. Test in Task 4.
- An unquoted `release_version: 1.2` is rejected by the format check. Expected: non-zero exit, error names the manifest. Test in Task 2.
- `--get 'release_version | .'` is looked up as a literal key and exits 1. Test in Task 1.

---

### Task 1: Generic --get in the manifest tool

**Files:**
- Modify: `scripts/release_manifest_tool.sh` (replace `read_release_version` with `read_key`; change the `--get)` branch of `main`)
- Test: `tests/test_release_manifest_tool.sh` (update the `--get amd-rocm` usage check; add R12 checks)

**Interfaces:**
- Consumes: `manifest_exists`, `check_failed`, `usage_error`, `MANIFEST`.
- Produces: `read_key <key>` prints the value of a top-level scalar key. Exits 1 with the key named when the key is absent or the value is a list or map. `main` accepts `--get <key>` with exactly one key.

- [ ] **Step 1: Write the failing tests**

Change the existing check at `tests/test_release_manifest_tool.sh:65` from "`--get amd-rocm` exits 2 with usage" to "`--get amd-rocm` exits 1 and names amd-rocm", using the fixture's manifest.

Add, each in its own fixture from `make_fixture`:
- "Getting a boolean key prints its value": manifest has `is_dev: true`; `--get is_dev` stdout is exactly `true`, exit 0.
- "Getting a string key prints its value": manifest has `label: hello`; stdout `hello`.
- "Getting a number key prints its value": manifest has `count: 3`; stdout `3`.
- "Getting an absent key exits with status 1": `--get nope`, exit 1.
- "Getting an absent key names the key in the error": stderr contains `nope`.
- "Getting a list key exits with status 1": `--get amd-rocm` exit 1, stderr contains `amd-rocm`.
- "Getting a map key exits with status 1": `--get support` exit 1.
- "Getting a key written as a yq expression looks up a literal key": `--get "release_version | ."` exit 1.

- [ ] **Step 2: Run the test to verify it fails**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_release_manifest_tool.sh`
Expected: FAIL on the `--get amd-rocm` check (exit 2 today) and on each new key check (usage error today).

- [ ] **Step 3: Implement `read_key`**

`read_key <key>`:
1. Call `manifest_exists`.
2. `K="$1" yq -r 'has(strenv(K))' "$MANIFEST"`. If the output is not `true`, call `check_failed "key not found: $1"`.
3. `K="$1" yq -r '.[strenv(K)] | tag' "$MANIFEST"`. If the output is not one of `!!str`, `!!int`, `!!float`, `!!bool`, call `check_failed "key is not a single-value key: $1"`.
4. Print `K="$1" yq -r '.[strenv(K)]' "$MANIFEST"`.

In `main`, the `--get)` branch requires exactly two arguments and calls `read_key "$2"`. Remove the `release_version` restriction. `--set`, `--list`, `--add` and `--delete` are unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_release_manifest_tool.sh` and `shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh`
Expected: all checks pass, shellcheck clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "Make manifest --get read any single-value key"
```

---

### Task 2: Build reads the version from the manifest

**Files:**
- Modify: `build-rocm.sh` (add `read_manifest_key <key>` and `resolve_image_version`; change `emit_tag_arguments` and the tag lines in `main`)
- Test: `tests/test_build_args.sh`

**Interfaces:**
- Consumes: `read_key` from Task 1 through `"$SCRIPT_DIR/scripts/release_manifest_tool.sh" --get <key>`.
- Produces: globals `IMAGE_VERSION` (the validated `release_version`) and `IMAGE_TAG` (equal to `IMAGE_VERSION` for now). `read_manifest_key <key>` prints the tool's value, or dies with a message naming `build-conf/project-release.yaml`. `resolve_image_version` sets `IMAGE_VERSION` and `IMAGE_TAG`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_build_args.sh`, change `EXPECTED_IMAGE_VERSION` (line 38) to read the manifest: `sed -n 's/^release_version: "\(.*\)"/\1/p' "$SRC/build-conf/project-release.yaml"`.

Add one test per scenario, using `run_dry`, `expect_line`, `reject_line` and `expect_stderr`:
- "A dry run tags the image with the manifest version": output contains the exact `--tag <reference>:1.2.0` line.
- "A changed manifest version changes the tag": in a copy of the tree, `release_version: "1.3.0"`; output contains `:1.3.0`.
- "A missing release_version exits non-zero": copy with the key removed; exit non-zero.
- "A missing release_version is named in the error": stderr contains `build-conf/project-release.yaml`.
- "A malformed release_version exits non-zero": copy with `release_version: "1.2"`; exit non-zero.
- "A malformed release_version is named in the error": stderr contains `build-conf/project-release.yaml`.
- "A malformed release_version (unquoted 1.2) is rejected": copy with `release_version: 1.2`; exit non-zero and stderr names the manifest.
- "A missing manifest exits non-zero": copy without `build-conf/project-release.yaml`; exit non-zero.
- "A missing manifest is named in the error": stderr names the manifest.
- "A missing yq exits non-zero": run with a PATH that has no `yq` (confirm with `command -v yq` under that PATH).
- "A missing yq is named in the error": stderr contains `yq`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh`
Expected: FAIL on the new checks. The script still takes the tag from `conf/build-config.env`.

- [ ] **Step 3: Implement**

`read_manifest_key <key>`:
1. If `command -v yq` finds nothing, call `die "yq v4 is required on PATH to read build-conf/project-release.yaml."`
2. Run `"$SCRIPT_DIR/scripts/release_manifest_tool.sh" --get "$1"`. If it fails, call `die "could not read '$1' from build-conf/project-release.yaml: <tool stderr>"`.
3. Print the value.

`resolve_image_version`:
1. `IMAGE_VERSION="$(read_manifest_key release_version)"`.
2. If it does not match `^[0-9]+\.[0-9]+\.[0-9]+$`, call `die "release_version '$IMAGE_VERSION' in build-conf/project-release.yaml must be MAJOR.MINOR.PATCH digits."`
3. `IMAGE_TAG="$IMAGE_VERSION"`.

Call `resolve_image_version` in `main` after the configuration files are loaded and before the image reference is built. Change `emit_tag_arguments` and the `--tag` line in `main` to use `IMAGE_TAG` in place of `RESOLVED_VALUE[VERSION]`. Leave `VERSION` in the key tables for now; Task 3 removes it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh` and `shellcheck build-rocm.sh tests/test_build_args.sh`
Expected: the new checks pass. Existing checks pass, or fail only where they pin `VERSION` from the build config; fix those expectations in this task. Shellcheck clean.

- [ ] **Step 5: Commit**

```bash
git add build-rocm.sh tests/test_build_args.sh
git commit -m "Read the image version from the release manifest"
```

---

### Task 3: VERSION leaves the build config

**Files:**
- Modify: `build-rocm.sh` (`KEY_AXIS`, `REQUIRED_KEYS`, `load_configuration_file`, `parse_arguments`)
- Modify: `conf/build-config.env` (remove the `VERSION=1.2.0` line and nothing else)
- Test: `tests/test_build_args.sh`

**Interfaces:**
- Consumes: `IMAGE_TAG` from Task 2.
- Produces: `VERSION` is in neither `KEY_AXIS` nor `REQUIRED_KEYS`. `load_configuration_file` skips a `VERSION` key with a warning. `parse_arguments` dies on `--set VERSION=...`.

- [ ] **Step 1: Write the failing tests**

Add, using the spec's scenarios:
- "The build config file does not declare VERSION": `grep -c '^VERSION=' conf/build-config.env` is `0`.
- "A VERSION line in the build config does not change the tag": copy the tree, append `VERSION=9.9.9` to the copy's `conf/build-config.env`; exit 0; output contains the exact `--tag <reference>:1.2.0` line.
- "A dry run emits no VERSION build argument": output has no line starting with `--build-arg VERSION=`.
- "Overriding VERSION with --set exits non-zero": `--set VERSION=9.9.9`; exit non-zero.
- "Overriding VERSION with --set names the manifest in its error": stderr contains `build-conf/project-release.yaml`.

Also review-focus tests:
- A shell `export VERSION=9.9.9` does not change the tag or add a build argument.
- A `VERSION=9.9.9` line in a copy's config prints a warning that names `VERSION` and the manifest.

Remove the `VERSION=` fixture lines at `tests/test_build_args.sh:156`, `:192`, `:216` and `:415`. Keep the fixtures otherwise unchanged.

- [ ] **Step 2: Run the test to verify it fails**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh`
Expected: FAIL. `VERSION` still resolves from the config, and `--set VERSION` is accepted.

- [ ] **Step 3: Implement**

- Remove `[VERSION]=neutral` from `KEY_AXIS` and `VERSION` from `REQUIRED_KEYS`.
- In `load_configuration_file`, when `key` is `VERSION`, call `warn "VERSION is read from build-conf/project-release.yaml, so the VERSION line in '$file_path' is ignored."` and skip the line.
- In `parse_arguments`, in the `--set)` branch, after `set_key` is computed: if `set_key` is `VERSION`, call `die "VERSION is read from build-conf/project-release.yaml. Change release_version there instead of passing --set VERSION."`
- Remove the `VERSION=1.2.0` line from `conf/build-config.env`.

Shell fallback loops over `REQUIRED_KEYS` and `KEY_AXIS`, so an exported `VERSION` is no longer read. No separate change is needed for it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh` and `shellcheck build-rocm.sh tests/test_build_args.sh`
Expected: all checks pass, shellcheck clean.

- [ ] **Step 5: Commit**

```bash
git add build-rocm.sh conf/build-config.env tests/test_build_args.sh
git commit -m "Take the image version from the manifest, not the build config"
```

---

### Task 4: is_dev appends -dev and suppresses latest

**Files:**
- Modify: `build-conf/project-release.yaml` (add `is_dev: false` directly after `release_version`)
- Modify: `build-rocm.sh` (`resolve_image_version`, `emit_tag_arguments`, the tag lines in `main`)
- Test: `tests/test_build_args.sh`

**Interfaces:**
- Consumes: `read_manifest_key` from Task 2.
- Produces: `IMAGE_IS_DEV` (`yes` or `no`). `IMAGE_TAG` becomes `<IMAGE_VERSION>-dev` when `IMAGE_IS_DEV` is `yes`. `emit_tag_arguments` prints the `latest` tag only when `IMAGE_IS_DEV` is `no`.

- [ ] **Step 1: Write the failing tests**

Add the R7 and R8 scenarios from the spec:
- "Getting is_dev ..." is no longer a build test; the tool reads the key generically (Task 1). Instead:
- "A missing is_dev exits non-zero": copy with no `is_dev` key; exit non-zero.
- "A missing is_dev is named in the error": stderr names the manifest.
- "A dev build tags the image with the -dev suffix": copy with `is_dev: true`; output contains the exact `--tag <reference>:1.2.0-dev` line.
- "A non-dev build tags the image without a suffix": `is_dev: false`; output contains the exact `--tag <reference>:1.2.0` line.
- "A dev build does not publish the latest tag": `is_dev: true`; output has no `--tag` line ending `:latest`.
- "A non-dev build publishes the latest tag": `is_dev: false`; output has a `--tag` line ending `:latest`.
- "A non-boolean is_dev stops the build with a non-zero status": copy with `is_dev: "yes"`; exit non-zero.
- "A non-boolean is_dev is named in the error": stderr names the manifest.
- Review focus: `is_dev: True` exits non-zero and names the manifest.

- [ ] **Step 2: Run the test to verify it fails**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh`
Expected: FAIL on the new checks.

- [ ] **Step 3: Implement**

In `resolve_image_version`, after reading `release_version`:
1. `is_dev="$(read_manifest_key is_dev)"`. This dies, naming the manifest, if the key is absent.
2. If `is_dev` is `true`, set `IMAGE_IS_DEV=yes`. If `false`, set `IMAGE_IS_DEV=no`. Anything else calls `die "is_dev '$is_dev' in build-conf/project-release.yaml must be true or false."`
3. `IMAGE_TAG="$IMAGE_VERSION"`, plus `-dev` when `IMAGE_IS_DEV` is `yes`.

Change `emit_tag_arguments` to print the `IMAGE_TAG` tag, and the `latest` tag only when `IMAGE_IS_DEV` is `no`. Make the same change to the tag lines in `main`.

Add `is_dev: false` to `build-conf/project-release.yaml` directly after `release_version`. Leave the rest of the file as it is.

- [ ] **Step 4: Run the test to verify it passes**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh` and `shellcheck build-rocm.sh tests/test_build_args.sh`
Expected: all checks pass, shellcheck clean. Also confirm `PATH=$PWD/.tmp/bin:$PATH bash tests/test_release_manifest_file.sh` still passes.

- [ ] **Step 5: Commit**

```bash
git add build-conf/project-release.yaml build-rocm.sh tests/test_build_args.sh
git commit -m "Append -dev to the image tag for dev builds"
```

---

### Task 5: Documentation names the manifest and the -dev suffix

**Files:**
- Modify: `CONTRIBUTING.md` (the Versioning paragraph, line 27)
- Modify: `README.md` (remove the `VERSION` row from the neutral-axis table, line 81; add `release_version` and `is_dev` to the manifest)
- Modify: `tests/test_contributing.sh` (update the expectations for the Versioning paragraph)

**Interfaces:**
- Consumes: the final behaviour from Tasks 2 to 4.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_contributing.sh`, next to the existing Versioning check at line 73:
- "CONTRIBUTING.md names the manifest in the Versioning section": the Versioning section contains `build-conf/project-release.yaml`.
- "CONTRIBUTING.md mentions the -dev suffix in the Versioning section": the section contains `-dev`.
- Keep the existing check for `iterates when Dockerfile.rocm changes`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_contributing.sh`
Expected: FAIL on the two new checks.

- [ ] **Step 3: Implement**

In `CONTRIBUTING.md` line 27, replace "tags it `<VERSION>` plus `latest`" and "The image version (`VERSION` in `conf/build-config.env`)" with the manifest and the -dev rule. Keep the phrase "iterates when Dockerfile.rocm changes" so the existing check still passes. Say that a dev build (`is_dev: true`) appends `-dev` and does not publish `latest`.

In `README.md`, remove the `VERSION` row from the neutral-axis table. Add `release_version` and `is_dev` to the build-config section in one row each, naming `build-conf/project-release.yaml` as their file.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_contributing.sh` and `bash tests/test_docs.sh`
Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md README.md tests/test_contributing.sh
git commit -m "Document the manifest as the image version source"
```

---

### Task 6: Full verification

**Files:** none changed.

- [ ] **Step 1: Run every suite**

Run: `PATH=$PWD/.tmp/bin:$PATH bash tests/test_build_args.sh && PATH=$PWD/.tmp/bin:$PATH bash tests/test_release_manifest_tool.sh && PATH=$PWD/.tmp/bin:$PATH bash tests/test_release_manifest_file.sh && bash tests/test_contributing.sh && bash tests/test_docs.sh`
Expected: each suite exits 0.

- [ ] **Step 2: Lint**

Run: `shellcheck build-rocm.sh scripts/release_manifest_tool.sh tests/test_build_args.sh tests/test_release_manifest_tool.sh tests/test_release_manifest_file.sh`
Expected: no output.

- [ ] **Step 3: Check the committed tree dry-run**

Run: `PATH=$PWD/.tmp/bin:$PATH ./build-rocm.sh --arch-env conf/amd-gfx1200.env --rocm-env conf/amd-7.14.1.env --llamacpp-env conf/llamacpp-v0.5.0.env --config-env conf/build-config.env --dry-run`
Expected: a `--tag ...:1.2.0` line and a `--tag ...:latest` line. No `--build-arg VERSION=` line.

- [ ] **Step 4: Confirm the committed manifest is unchanged by the tests**

Run: `git status --short build-conf conf scripts tests`
Expected: no output.

Docker build is not part of this plan's verification. The devcontainer `yq` check was done in `e91b742`.

---

## Self-Review

- **Spec coverage:** R1 is Task 2. R2 and R3 are Task 3. R4 is Task 3. R5 is Task 2. R6 is Task 5. R7 and R8 are Task 4. R9 is Task 5. Tool R12 is Task 1.
- **Type consistency:** `read_key` (Task 1) is used by `read_manifest_key` (Task 2). `IMAGE_VERSION`, `IMAGE_TAG` and `IMAGE_IS_DEV` are introduced in Tasks 2 and 4 and used only after that.
- **Review Focus:** each of the five lines has a test in Tasks 1 to 4.
