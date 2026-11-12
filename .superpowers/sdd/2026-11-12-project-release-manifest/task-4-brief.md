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

