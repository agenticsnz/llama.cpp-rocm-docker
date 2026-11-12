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

