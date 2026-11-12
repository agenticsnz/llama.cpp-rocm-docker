# Task 4 report: List an axis

## Status

DONE

## Files changed

- `scripts/release_manifest_tool.sh`: `list_axis_values` body replaced. It calls `manifest_exists`, then `yq -r ".support.$1[]" "$MANIFEST"`. Signature unchanged.
- `tests/test_release_manifest_tool.sh`: new section "list prints axis values" with three checks, placed before the summary lines.

## Tests added (R8 scenarios)

1. Listing amd-rocm prints its values in file order (`amd-7.14.1`, `amd-10.1.0`), exit 0.
2. Listing an axis with no values prints nothing, exit 0. The fixture under `.tmp/` sets `amd-arch` to `[]` with `yq -i`. The committed manifest is not touched.
3. Listing with a missing manifest exits 1, names `build-conf/project-release.yaml` on stderr, and does not create the file.

## RED output (before implementation)

```
== list prints axis values ==
  FAIL --list amd-rocm: exit 1, expected 0
  FAIL --list amd-arch with empty axis: exit 1, expected 0
  FAIL --list with missing manifest: stderr does not name the manifest

=== 14 passed, 3 failed ===
```

The 14 earlier checks passed on the same run.

## GREEN output (after implementation)

```
== list prints axis values ==
  ok   --list amd-rocm prints its values in file order and exits 0
  ok   --list amd-arch with an empty axis prints nothing and exits 0
  ok   --list with missing manifest exits 1, names the file, creates nothing

=== 17 passed, 0 failed ===
```

Exit status of the test script: 0.

## Shellcheck

`shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh` produced no findings and exited 0.

## Commit

Commit SHA and subject: see the reply to the parent session (recorded after commit).

## Concerns

None. The brief listed only two list scenarios. I also added the missing-manifest scenario from R8, because the spec lists it there and the test file must cover R8.

## Commit (final)

SHA `bbfe79c`, subject "List axis values in the release manifest tool".
