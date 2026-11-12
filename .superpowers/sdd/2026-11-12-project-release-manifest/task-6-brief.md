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

