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

