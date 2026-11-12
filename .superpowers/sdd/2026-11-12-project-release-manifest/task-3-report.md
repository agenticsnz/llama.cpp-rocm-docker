# Task 3 report: Read and write release_version

Status: DONE_WITH_CONCERNS
Commit: a813465 Read and write release_version in the release manifest tool

## RED (before implementation, stubs in place)

```
== no command is a usage error ==
  ok   no arguments exits 2 with usage

== release_version commands reject an axis name ==
  ok   --get amd-rocm exits 2 with usage

== axis commands reject an unknown axis name ==
  ok   --add gpu gfx1200 exits 2 and leaves the manifest unchanged
  ok   --list gpu exits 2 with usage

== set and list reject the wrong top-level name ==
  ok   --set amd-rocm 1.0.0 exits 2 with usage
  ok   --list release_version exits 2 with usage

== release_version read and write ==
  FAIL --get from /tmp: exit 1, stdout '', expected exit 0 and '1.2.0'
  FAIL --set 1.3.0: exit 1, expected 0
  ok   --set 1.3 exits 1 and leaves the manifest unchanged
  ok   --set '1.3.0"; x' exits 1 and leaves the manifest unchanged
  FAIL --get on unquoted 1.2: exit 1, stdout '', expected exit 0 and '1.2'
  FAIL --set 1.3.0 over unquoted 1.2: exit 1, expected 0

== release_version with a missing manifest fails ==
  FAIL --get with missing manifest: stderr does not name the manifest
  ok   --set with missing manifest exits 1 and creates nothing

=== 9 passed, 5 failed ===
exit 1
```

The two rejection checks (`--set 1.3`, `--set '1.3.0"; x'`) pass against the stubs because the stubs also exit 1 and leave the file alone. They are real checks once the implementation exists.

## GREEN (after implementation)

```
== no command is a usage error ==
  ok   no arguments exits 2 with usage

== release_version commands reject an axis name ==
  ok   --get amd-rocm exits 2 with usage

== axis commands reject an unknown axis name ==
  ok   --add gpu gfx1200 exits 2 and leaves the manifest unchanged
  ok   --list gpu exits 2 with usage

== set and list reject the wrong top-level name ==
  ok   --set amd-rocm 1.0.0 exits 2 with usage
  ok   --list release_version exits 2 with usage

== release_version read and write ==
  ok   --get from /tmp prints 1.2.0 and exits 0
  ok   --set 1.3.0 replaces the version and keeps it quoted
  ok   --set 1.3 exits 1 and leaves the manifest unchanged
  ok   --set '1.3.0"; x' exits 1 and leaves the manifest unchanged
  ok   --get on unquoted release_version: 1.2 prints 1.2
  ok   --set 1.3.0 over unquoted 1.2 writes a quoted !!str

== release_version with a missing manifest fails ==
  ok   --get with missing manifest exits 1, names the file, creates nothing
  ok   --set with missing manifest exits 1 and creates nothing

=== 14 passed, 0 failed ===
exit 0
```

## Shellcheck

`shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh`: no findings, exit 0.

## Deviation from the brief: style operator on write

The brief specifies `V="$1" yq -i '.release_version = strenv(V)'`. I ran that against yq v4.54.1 on an unquoted `release_version: 1.2`. The result was `release_version: 1.3.0`, unquoted, tagged `!!str`. The spec (R7 scenario "rewrites an unquoted numeric value as a quoted string", and R3) requires `release_version: "1.3.0"`. The brief's reasoning, "quoting is preserved because strenv produces a string node", holds only when the old node was already quoted.

The implementation adds `| .release_version style = "double"`:

```
V="$1" yq -i '.release_version = strenv(V) | .release_version style = "double"' "$MANIFEST"
```

Values still reach yq only through `strenv`, so the Global Constraint holds. The probe confirmed that both starting forms (quoted and unquoted) then write `"1.3.0"` with `!!str`, and that the quote-injection value is still rejected before yq runs.

## Other notes

- `manifest_exists` exits 1 and names `$MANIFEST` (an absolute path ending in `build-conf/project-release.yaml`). It runs before every read and write, so a missing manifest is never created.
- `--get` and `--set` rejecting axis names was already covered by the Task 2 tests (`--get amd-rocm`, `--set amd-rocm 1.0.0`). No new axis tests were needed.
- Added the spec's R7 scenarios that the brief did not list: the unquoted-numeric `--get` case and the missing-manifest `--get` and `--set` cases.
- The test file's trap removes `.tmp/release-manifest-tests`. The committed `build-conf/project-release.yaml` and `conf/` are untouched (`git status` clean apart from the two files, now committed).
- Not pushed.

## Files changed

- `scripts/release_manifest_tool.sh`: added `manifest_exists`; bodies for `is_valid_release_version`, `read_release_version`, `write_release_version`. Stub signatures unchanged.
- `tests/test_release_manifest_tool.sh`: added the `with_release_version_line` helper and 10 new checks in two sections.
