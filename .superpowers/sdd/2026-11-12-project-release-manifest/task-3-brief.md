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
- `--set release_version '1.3.0"; x'` exits `1` and leaves the file unchanged;
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

