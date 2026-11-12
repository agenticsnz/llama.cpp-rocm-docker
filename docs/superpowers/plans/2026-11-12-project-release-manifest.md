# Project Release Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `build-conf/project-release.yaml` and a helper script that reads and writes its `release_version` and axis lists with `yq` v4.

**Architecture:** A YAML manifest holds `release_version` and a `support` map of three block sequences (`llama-cpp`, `amd-rocm`, `amd-arch`), each listing env file stems. `scripts/release_manifest_tool.sh` resolves the manifest from its own location, reads and writes it with `yq -i`, and checks axis values against `CONF_DIR`, which defaults to `$REPO_ROOT/conf` and can be overridden by the environment.

**Tech Stack:** bash, `yq` v4.54.1 (pinned in `.devcontainer/Dockerfile.plain` and `.devcontainer/Dockerfile.opencode`), shellcheck.

**Spec:** `docs/superpowers/specs/2026-11-11-project-release-manifest-design.md`. Every scenario named in a task below is defined in that spec under the requirement given; the scenario title is the test name.

## Global Constraints

- `release_version` is always double-quoted in the manifest and the script writes it that way.
- Values reach `yq` only through `strenv(...)`, never by interpolating them into the expression. The spec's skeleton comments show interpolation; this plan overrides them.
- `CONF_DIR` is a `readonly` constant: `readonly CONF_DIR="${CONF_DIR:-$REPO_ROOT/conf}"`. `MANIFEST` is fixed to `$REPO_ROOT/build-conf/project-release.yaml`.
- Exit codes: `0` success, `1` check failed with the file unchanged, `2` usage error.
- Test files live in `tests/`, use the `note_pass` / `note_fail` / `PASS` / `FAIL` pattern of `tests/test_contributing.sh`, and exit non-zero on any failure.
- Each test function runs in its own fresh fixture under `.tmp/` (gitignored) and never touches the committed manifest or `conf/`.
- Commit after each task. Commit messages follow `CONTRIBUTING.md` style: imperative subject under 72 characters, no co-author lines.

## Review Focus

- A value containing quotes or `yq` syntax is stored literally by `--add`. `--set` rejects it through the format check. Expected: `--add` with `amd"x` round-trips through `--list` unchanged, and `--set` with `1.3.0"; x` exits `1` with the file unchanged.
- A manifest that is missing: every command exits `1` and does not create the file. Expected: a clear message on stderr and no file created.
- Deleting the last value from an axis leaves an empty block sequence, and `--list` on it prints nothing with exit `0`. Expected: no error for an empty axis.
- Deleting a value that is a prefix of a listed value (`amd-7.14` against `amd-7.14.1`) removes nothing and exits `1`. Expected: the list is unchanged.
- An unquoted numeric `release_version: 1.2` in the file: `--get` prints `1.2`, and `--set` rewrites it as the quoted string `"1.3.0"`. Expected: the value becomes a string after the first write.

---

### Task 1: Manifest file and yq read and write behaviour

**Files:**
- Create: `build-conf/project-release.yaml`
- Test: `tests/test_release_manifest_file.sh`

**Interfaces:**
- Consumes: `yq` v4.54.1 on `PATH`.
- Produces: the manifest with the shape in spec section "The file". Later tasks read `release_version` and `support.<axis>`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_release_manifest_file.sh`. It runs one function per scenario, each in a fresh fixture under `.tmp/`:

- The manifest exists at the path (R1: "The manifest file exists at build-conf/project-release.yaml").
- Reading returns `1.2.0` and reports `!!str` (R2: both scenarios).
- Writing `1.3.0` replaces the value, keeps it quoted, and reports `!!str` (R3: three scenarios; the numeric-looking case writes `"1.3"` and reports `!!str`).
- `yq -o=json '.support | keys'` returns `["llama-cpp","amd-rocm","amd-arch"]` (R4).
- The failure behaviour from R6: a missing file exits `1`, writing a missing file exits `1` and does not create it, a missing key returns `null` with exit `0`, an unquoted `1.2` reports `!!float`.

The R6 scenarios test `yq` directly, so they pin the behaviour later tasks rely on.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_file.sh`
Expected: FAIL on "manifest file exists" and the read, write and keys checks, because the manifest does not exist yet. The exit status is non-zero.

- [ ] **Step 3: Create the manifest**

Create `build-conf/project-release.yaml` with exactly the content in spec section "The file": `release_version: "1.2.0"` and the three block-sequence axes with the stems `llamacpp-v0.5.0`, `amd-7.14.1`, `amd-10.1.0`, `amd-gfx1200`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_file.sh`
Expected: every check prints `ok`, the summary shows zero failures, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add build-conf/project-release.yaml tests/test_release_manifest_file.sh
git commit -m "Add project release manifest and its yq behaviour tests"
```

---

### Task 2: Helper script skeleton and argument checks

**Files:**
- Create: `scripts/release_manifest_tool.sh`
- Test: `tests/test_release_manifest_tool.sh`

**Interfaces:**
- Consumes: the manifest from Task 1.
- Produces: `main`, `usage_error`, `check_failed`, `is_axis`, and the stubs `read_release_version`, `write_release_version <value>`, `list_axis_values <axis>`, `add_axis_value <axis> <value>`, `delete_axis_value <axis> <value>`. Tasks 3 to 6 fill in the stubs. Each stub returns `1` until then.
- The test file also gains the fixture helper used by Tasks 3 to 6: `make_fixture <name>` creates `.tmp/<name>/` containing a copy of `scripts/`, a copy of `build-conf/`, and a `conf/` directory with the four stems from Task 1 (`llamacpp-v0.5.0.env`, `amd-7.14.1.env`, `amd-10.1.0.env`, `amd-gfx1200.env`, each empty). It prints the fixture path. Each test calls it with a unique name and runs the script from that copy, so the repository is never touched.

- [ ] **Step 1: Write the failing test**

Cover the R11 scenarios: no arguments exits `2` with usage on stderr; `--get amd-rocm` exits `2`; `--add gpu gfx1200` exits `2` and leaves the manifest byte-identical (compare with `cmp` against a saved copy); and the same argument checks for `--set` with a wrong name and `--list` with `release_version`. Add the R8 scenario "Listing an unknown top-level name is a usage error" here too (`--list gpu` exits `2`).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: FAIL, because `scripts/release_manifest_tool.sh` does not exist. Every usage check fails.

- [ ] **Step 3: Implement the skeleton**

Create `scripts/release_manifest_tool.sh` from the skeleton in spec section "The helper script", with these changes:
- `CONF_DIR` is `readonly CONF_DIR="${CONF_DIR:-$REPO_ROOT/conf}"`.
- `main` keeps the `case` dispatch and the argument-count checks from the spec.
- `usage_error` prints its message and the usage text to stderr and exits `2`.
- `is_axis` returns `0` only for the three names in `AXES`. `main` calls `usage_error` when an axis argument fails it, before any stub runs.
- The stubs return `1` as they do in the spec.

Run `chmod +x scripts/release_manifest_tool.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: all usage checks print `ok`, exit `0`. Then run `shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh` and expect no output.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "Add release manifest tool skeleton and argument checks"
```

---

### Task 3: Read and write release_version

**Files:**
- Modify: `scripts/release_manifest_tool.sh` (`read_release_version`, `write_release_version`, new `is_valid_release_version`)
- Modify: `tests/test_release_manifest_tool.sh`

**Interfaces:**
- Consumes: `MANIFEST`, `main` from Task 2.
- Produces: `is_valid_release_version <value>` returns `0` only for digits in `MAJOR.MINOR.PATCH`. `read_release_version` prints the value, `write_release_version <value>` rewrites it as a quoted string.

- [ ] **Step 1: Write the failing tests**

From R7, one test function per scenario:
- "Getting release_version works from another working directory": run the tool from `/tmp` (a path outside the repo) via its absolute fixture path; stdout is `1.2.0`, exit `0`.
- "Setting release_version replaces the stored version": after `--set release_version 1.3.0`, the file contains `release_version: "1.3.0"` and the exit is `0`.
- "Setting release_version rejects a value that is not MAJOR.MINOR.PATCH": `--set release_version 1.3` exits `1` and the file still holds `"1.2.0"`.

From the Review Focus list, add:
- the quote-and-syntax value round-trips through `--set` and `--get` unchanged;
- an unquoted `release_version: 1.2` in the fixture reads as `1.2` and, after `--set release_version 1.3.0`, reports `!!str`.

Also check that `--get` and `--set` reject axis names, the R11 scenario "Getting an axis name as release_version is a usage error".

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: FAIL on the new tests. The stubs return `1`.

- [ ] **Step 3: Implement**

- `manifest_exists`: returns `check_failed` (exit `1`) when `$MANIFEST` is not a regular file. Every command that touches the manifest calls it first, including the list, add and delete commands in later tasks.
- `read_release_version`: calls `manifest_exists`, then `yq -r '.release_version' "$MANIFEST"`.
- `is_valid_release_version`: an anchored regex, `^[0-9]+\.[0-9]+\.[0-9]+$`.
- `write_release_version <value>`: returns `check_failed` (exit `1`) when the value is invalid. Otherwise it runs `V="$1" yq -i '.release_version = strenv(V)' "$MANIFEST"`. Quoting is preserved because `strenv` produces a string node.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: all checks print `ok`, exit `0`. Run `shellcheck` on the script and the test.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "Read and write release_version in the release manifest tool"
```

---

### Task 4: List an axis

**Files:**
- Modify: `scripts/release_manifest_tool.sh` (`list_axis_values`)
- Modify: `tests/test_release_manifest_tool.sh`

**Interfaces:**
- Consumes: `is_axis` from Task 2.
- Produces: `list_axis_values <axis>` prints one value per line in file order.

- [ ] **Step 1: Write the failing tests**

From R8:
- "Listing amd-rocm prints its values in file order": stdout is `amd-7.14.1` then `amd-10.1.0`, one per line, exit `0`.
- Plus the Review Focus case: an axis whose block sequence is empty (`amd-arch: []` in the fixture) prints nothing and exits `0`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: FAIL on both list tests (the stub returns `1`).

- [ ] **Step 3: Implement**

`list_axis_values <axis>`: calls `manifest_exists`, then `yq -r ".support.$1[]" "$MANIFEST"`. The axis name is safe to interpolate because `main` has already rejected anything that is not one of the three names. An empty axis produces no output from `yq`, so the function exits `0`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: all checks `ok`, exit `0`. Run `shellcheck`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "List axis values in the release manifest tool"
```

---

### Task 5: Add a value to an axis

**Files:**
- Modify: `scripts/release_manifest_tool.sh` (`add_axis_value`, new `axis_value_exists` and `env_file_exists` helpers)
- Modify: `tests/test_release_manifest_tool.sh`

**Interfaces:**
- Consumes: `CONF_DIR`, `is_axis`, `list_axis_values` from Task 4.
- Produces: `axis_value_exists <axis> <value>` returns `0` when the value is in the list. `env_file_exists <value>` returns `0` when `$CONF_DIR/<value>.env` is a regular file.

- [ ] **Step 1: Write the failing tests**

From R9, one test per scenario:
- "Adding a new value appends it to the axis list": the fixture contains `conf/amd-8.0.0.env`. After `--add amd-rocm amd-8.0.0`, the list is `amd-7.14.1`, `amd-10.1.0`, `amd-8.0.0` and exit is `0`.
- "Adding a value already in the axis list is rejected": `--add amd-rocm amd-10.1.0` exits `1` and the list is unchanged.
- "Adding a value with no matching env file is rejected": `--add amd-arch amd-gfx9999` exits `1` and the list is unchanged.

Also from the Review Focus list: `--add amd-rocm 'amd"x'` with a fixture file `conf/amd"x.env` exits `0`, and `--list amd-rocm` then ends with `amd"x` exactly.

Also test that `CONF_DIR` set in the environment is the directory the existence check reads: a fixture where the env file exists only in a second directory, passed as `CONF_DIR=<dir>`, is accepted. This is the override that Task 2's readonly line must keep.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: FAIL on the three R9 tests and the override test.

- [ ] **Step 3: Implement**

`add_axis_value <axis> <value>`, in this order:
1. `axis_value_exists`: if present, `check_failed` (exit `1`).
2. `env_file_exists`: if missing, `check_failed`.
3. `V="$2" yq -i ".support.$1 += [strenv(V)]" "$MANIFEST"`.

Both checks run before any write, so a failed check leaves the file unchanged. Tell the builder to use `strenv` here as well, for the same reason as Task 3.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: all checks `ok`, exit `0`. Run `shellcheck`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "Add values to axis lists in the release manifest tool"
```

---

### Task 6: Delete one value from an axis

**Files:**
- Modify: `scripts/release_manifest_tool.sh` (`delete_axis_value`)
- Modify: `tests/test_release_manifest_tool.sh`

**Interfaces:**
- Consumes: `axis_value_exists` from Task 5.
- Produces: `delete_axis_value <axis> <value>` removes exactly one matching entry.

- [ ] **Step 1: Write the failing tests**

From R10:
- "Deleting a value removes that value from the axis list": `--delete amd-rocm amd-10.1.0` leaves `amd-7.14.1`, exit `0`.
- "Deleting a value leaves the other axis lists unchanged": after the same delete, `amd-arch` still holds `amd-gfx1200`.
- "Deleting a value not in the axis list is rejected": `--delete amd-rocm amd-9.9.9` exits `1` and the list is unchanged.

From the Review Focus list:
- Deleting the last value leaves `amd-rocm: []`, and `--list amd-rocm` then prints nothing and exits `0`.
- Deleting `amd-7.14` when the list holds `amd-7.14.1` exits `1` and the list is unchanged.
- Deleting `amd-7.14.1` from a list that also holds `amd-7.14.10` removes only `amd-7.14.1`. Expected: `amd-7.14.10` stays.

Also test that `--delete` on a manifest missing is a failure: exits `1` and does not create the file.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: FAIL on every new test.

- [ ] **Step 3: Implement**

`delete_axis_value <axis> <value>`:
1. `axis_value_exists`: if absent, `check_failed` (exit `1`).
2. `V="$2" yq -i ".support.$1 |= del(.[] | select(. == strenv(V)))" "$MANIFEST"`.

The comparison is an exact `==` match, so prefixes and near-matches do not delete anything. Call `manifest_exists` first, as Task 3 requires.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_release_manifest_tool.sh`
Expected: all checks `ok`, exit `0`. Run `shellcheck`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh
git commit -m "Delete single values from axis lists in the release manifest tool"
```

---

### Task 7: Devcontainer check and full verification

**Files:**
- No file changes expected.

**Interfaces:**
- Consumes: all earlier tasks.

- [ ] **Step 1: Verify the devcontainer reports yq v4.54.1 (spec R5)**

Build the plain image and run the check:

Run: `docker build -f .devcontainer/Dockerfile.plain -t yq-check:plain .devcontainer && docker run --rm yq-check:plain yq --version`
Expected: output contains `version v4.54.1`. Then `docker rmi yq-check:plain`.

- [ ] **Step 2: Run the full suite and lint**

Run: `bash tests/test_release_manifest_file.sh && bash tests/test_release_manifest_tool.sh && shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_file.sh tests/test_release_manifest_tool.sh`
Expected: both suites exit `0` and shellcheck prints nothing.

- [ ] **Step 3: Confirm the committed manifest is unchanged by tests**

Run: `git status --short build-conf conf`
Expected: no output. Tests must not change the committed manifest or `conf/`.

- [ ] **Step 4: Clean up the fixtures**

Run: `rm -rf .tmp/release-manifest-*`
Expected: no error. Commit nothing in this task.

---

## Self-Review

- **Spec coverage:** R1 and R2 through R4 are in Task 1. R5 is in Task 7. R6 is in Task 1. R7 is in Task 3. R8 is in Task 4. R9 is in Task 5. R10 is in Task 6. R11 is in Task 2 and Task 3. The `CONF_DIR` override is in Task 5. Every scenario title in the spec appears in one of the tasks.
- **Type consistency:** `read_release_version`, `write_release_version <value>`, `list_axis_values <axis>`, `add_axis_value <axis> <value>` and `delete_axis_value <axis> <value>` keep the names from the skeleton in Task 2. The helpers `is_valid_release_version`, `axis_value_exists` and `env_file_exists` are introduced in Tasks 3 and 5 and used only after that.
- **Review Focus:** each of the five items has a test in Tasks 3, 4 or 6.
