# Task 5 Report: Add a value to an axis

Status: DONE
Commit: 4f8d6d1 Add values to axis lists in the release manifest tool

## RED output

Tests run before implementation (stub `add_axis_value` returned 1):

```
== add appends a value to an axis ==
  FAIL --add amd-rocm amd-8.0.0: exit 1, expected 0
  ok   --add duplicate amd-10.1.0 exits 1 and leaves the manifest unchanged
  ok   --add amd-arch amd-gfx9999 exits 1 and leaves the manifest unchanged
  FAIL --add amd-rocm 'amd"x': exit 1, expected 0
  FAIL CONF_DIR override: exit 1, expected 0

=== 19 passed, 3 failed ===
exit=1
```

The two rejection tests pass on the stub only because the stub always exits 1. They are meaningful only once the positive path works, which GREEN confirms.

## Implementation

`scripts/release_manifest_tool.sh`:

- `axis_value_exists <axis> <value>`: calls `manifest_exists`, then `V="$2" yq -e ".support.$1[] | select(. == strenv(V))"`. Returns 0 on match.
- `env_file_exists <value>`: `[ -f "$CONF_DIR/$1.env" ]`.
- `add_axis_value`: duplicate check, then env-file check (both before any write), then `V="$2" yq -i ".support.$1 += [strenv(V)]"`.

Stub signatures are unchanged; the new helpers are added between `list_axis_values` and `add_axis_value`.

## GREEN output

```
== add appends a value to an axis ==
  ok   --add amd-rocm amd-8.0.0 appends the value and exits 0
  ok   --add duplicate amd-10.1.0 exits 1 and leaves the manifest unchanged
  ok   --add amd-arch amd-gfx9999 exits 1 and leaves the manifest unchanged
  ok   --add amd-rocm 'amd"x' exits 0 and lists the value exactly
  ok   CONF_DIR override: env file in that directory is accepted

=== 22 passed, 0 failed ===
exit=0
```

(Earlier sections of the output are unchanged from RED and all `ok`.)

## Shellcheck

`shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh` (shellcheck 0.9.0): no findings, exit 0.

## Files changed

- `scripts/release_manifest_tool.sh` (+14 / -3 lines in the add section)
- `tests/test_release_manifest_tool.sh` (+74 lines: five new checks in an "add appends a value to an axis" section)

The committed `build-conf/project-release.yaml` and `conf/` are untouched. All test fixtures live under `.tmp/release-manifest-tests`, which the test script removes on exit.

## Notes

- The no-match case for `yq -e` returns non-zero, which is what the `select` check relies on. The "append" test covers this, since a non-match must be treated as absent for the add to proceed.
- The CONF_DIR override check relies on `CONF_DIR` being read from the environment through the existing `${CONF_DIR:-...}` default in the readonly line, which is unchanged.
- The commit message body is two lines and contains no co-author or attribution lines. Nothing was pushed.
