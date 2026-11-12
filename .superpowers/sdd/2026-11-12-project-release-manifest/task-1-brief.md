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

