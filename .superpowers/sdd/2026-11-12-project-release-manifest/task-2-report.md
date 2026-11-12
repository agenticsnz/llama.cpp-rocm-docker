# Task 2 report: Helper script skeleton and argument checks

## Status

DONE. Commit `eff7afc` "Add release manifest tool skeleton and argument checks", on branch `enhancement/issue-19-project-release-yaml-source`. Not pushed.

## What I did

1. Read the brief, the spec (R7 to R11 and the skeleton), and `tests/test_contributing.sh` for house style.
2. Wrote `tests/test_release_manifest_tool.sh` first. It has the `note_pass` / `note_fail` counters, a `make_fixture <name>` helper, and an `expect_usage_error` helper. The helper asserts exit `2`, `Usage:` on stderr, and a byte-identical manifest (checked with `cmp` against a copy saved before the call).
3. Ran the test for RED. The script did not exist, so every fixture copy failed.
4. Created `scripts/release_manifest_tool.sh` from the spec skeleton, with the brief's changes:
   - `CONF_DIR` is `readonly CONF_DIR="${CONF_DIR:-$REPO_ROOT/conf}"`.
   - `usage_error` prints its message and the usage text to stderr and exits `2`.
   - `is_axis` returns `0` only for the three names in `AXES`, and `main` calls `usage_error` for a bad axis before any stub runs.
   - `--list`, `--add` and `--delete` check `is_axis "$2"`. `--get` and `--set` check the `release_version` literal, as the skeleton does.
   - All stubs return `1`. `chmod +x` applied.
5. Ran the test for GREEN. Shellcheck then reported findings, which I fixed (see below). Re-ran GREEN.
6. Staged the two files by name and committed.

## RED output

```
== no command is a usage error ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL no arguments exits 2 with usage: exit 127, expected 2

== release_version commands reject an axis name ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL --get amd-rocm exits 2 with usage: exit 127, expected 2

== axis commands reject an unknown axis name ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL --add gpu gfx1200 exits 2 and leaves the manifest unchanged: exit 127, expected 2
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL --list gpu exits 2 with usage: exit 127, expected 2

== set and list reject the wrong top-level name ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL --set amd-rocm 1.0.0 exits 2 with usage: exit 127, expected 2
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/scripts': No such file or directory
  FAIL --list release_version exits 2 with usage: exit 127, expected 2

=== 0 passed, 6 failed ===
```

## GREEN output

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

=== 6 passed, 0 failed ===
```

Exit status of the test run: `0`.

## Shellcheck

First run, before fixes, on both files: 
- SC2155 on `readonly REPO_ROOT="$(...)"`. Fixed by splitting the assignment from `readonly`.
- SC2034 on `MANIFEST`, which is used only by the stubs' yq comments for now. Suppressed with `# shellcheck disable=SC2034` and a comment saying Task 3 uses it.
- SC2015 (info) on five `[ ... ] && ... || usage_error` arms in `main`. Suppressed with a directive above `main`. The `||` is the intended exit path.

Final run: `shellcheck scripts/release_manifest_tool.sh tests/test_release_manifest_tool.sh` produces no output, exit `0`.

## Files changed

- Created `scripts/release_manifest_tool.sh` (mode `755`).
- Created `tests/test_release_manifest_tool.sh`.
- This report, `.superpowers/sdd/2026-11-12-project-release-manifest/task-2-report.md`, is written but not committed, as the brief asks for a file in the workspace.

The committed manifest is unchanged (`cmp` against `git show HEAD:` passes). `conf/` is untouched.

## Deviations and notes

- **Fixture location:** the brief says `make_fixture` creates `.tmp/<name>/`. I put fixtures under `.tmp/release-manifest-tests/<name>/`, and the test file's `EXIT` trap removes `.tmp/release-manifest-tests/` when it finishes. This keeps `.tmp/` clean without a per-test cleanup. Tasks 3 to 6 get the same behaviour from the shared helper. If the controller wants the literal `.tmp/<name>/` path, change `FIXTURE_ROOT` and drop the trap.
- **Extra stub:** `is_valid_release_version` is in the spec skeleton but not in the brief's produces list. I included it as a stub returning `1`, so Task 3 fills it in.
- **`scripts/` did not exist before this task.** The `scripts/` directory was created by this task and contains only `release_manifest_tool.sh`.
- The `--set` format check is not implemented here; `--set` currently fails at the stub (exit `1`) for any valid release_version. This is expected until Task 3.
- Not run: the rest of the R-scenarios. Those belong to Tasks 3 to 6.
- Co-author lines: none. Commit made without attribution.

## Commit

- SHA: `eff7afc`
- Subject: `Add release manifest tool skeleton and argument checks`
