# Fix round 1 report

Branch: enhancement/issue-19-project-release-yaml-source
Base HEAD: 1254abd
Fix commit: e966eb653df3fdaee1cba7546fbd26bed418acb3 "Match axis names exactly in the release manifest tool"

## Finding 1: is_axis substring match

### RED

Tests added to tests/test_release_manifest_tool.sh: `--list "amd-rocm amd-arch"`, `--add "llama-cpp amd-rocm" x`, `--delete "amd-rocm amd-arch" x`, each expecting exit 2, usage on stderr, and an unchanged manifest.

```
== axis commands reject an unknown axis name ==
  ok   --add gpu gfx1200 exits 2 and leaves the manifest unchanged
  ok   --list gpu exits 2 with usage
  FAIL --list 'amd-rocm amd-arch' exits 2 with usage: exit 1, expected 2
  FAIL --add 'llama-cpp amd-rocm' x exits 2 and leaves the manifest unchanged: exit 1, expected 2
  FAIL --delete 'amd-rocm amd-arch' x exits 2 with usage: exit 1, expected 2
...
=== 30 passed, 3 failed ===
```

### Fix

`is_axis` in scripts/release_manifest_tool.sh now loops over the words of `$AXES` and compares each with `[ "$axis" = "$1" ]`. `AXES` is kept as the single source of the axis names. The substring `case` match is gone.

### GREEN

```
=== 33 passed, 0 failed ===
```

(The 33 includes the three new compound-axis tests and the new missing-manifest test.)

## Finding 2: missing test for "Adding a value with a missing manifest fails"

Test added to tests/test_release_manifest_tool.sh using `make_fixture`. It creates `conf/amd-8.0.0.env`, removes the manifest, runs `--add amd-rocm amd-8.0.0`, and checks exit 1 and that the manifest is not created.

This test passes against the code as it was before the fix (`manifest_exists` in `axis_value_exists` already exits 1). It was not a RED test. Output:

```
  ok   --add with missing manifest exits 1 and creates nothing
```

## Finding 3: fixture directory left behind by tests/test_release_manifest_file.sh

RED: the HEAD version of the file was run from a temporary copy. Afterwards `.tmp/release-manifest-file-tests` still existed.

```
HEAD version exit=0
.tmp/release-manifest-file-tests        <- left behind
```

Fix: added `trap 'rm -rf "$FIXTURE_ROOT"' EXIT` after the note helpers, the same line used in tests/test_release_manifest_tool.sh.

GREEN: after running the fixed file, `ls -d .tmp/release-manifest-file-tests` reports no such directory. The file suite result is `exit 0`.

## Verification

- `bash tests/test_release_manifest_tool.sh`: 33 passed, 0 failed, exit 0.
- `bash tests/test_release_manifest_file.sh`: exit 0 (the suite prints its own pass count).
- `shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_file.sh tests/test_release_manifest_tool.sh`: exit 0, no findings.
- Not changed: build-conf/project-release.yaml, conf/, stub signatures.
- Staged by name: scripts/release_manifest_tool.sh, tests/test_release_manifest_file.sh, tests/test_release_manifest_tool.sh.
- Commit message has no co-author lines. Not pushed.

## Concerns

None outstanding. The `.superpowers/` tree is gitignored, so this report is not part of the commit.
