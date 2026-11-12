# Task 1 Report: Manifest file and yq read and write behaviour

Status: DONE
Commit: ee86bb2 "Add project release manifest and its yq behaviour tests"
Branch: enhancement/issue-19-project-release-yaml-source

## What I did

1. Found `tests/test_release_manifest_file.sh` already present and untracked, matching the brief's scope. Read it, the brief, spec section "The file" and R1 to R6, and `tests/test_contributing.sh` for house style.
2. Confirmed `yq` on PATH with `export PATH=/workspaces/llama.cpp-rocm-docker/.tmp/bin:$PATH`: `yq (https://github.com/mikefarah/yq/) version v4.54.1`.
3. Fixed one flaw in the existing test before the RED run (details under Concerns). The R2, R3 and R4 checks wrote their own inline manifest, so they did not depend on the committed file. They now copy the committed `build-conf/project-release.yaml` into a fixture under `.tmp/` via `copy_manifest`, replacing `write_manifest`.
4. Ran the test for RED.
5. Created `build-conf/project-release.yaml` exactly as in the spec's "The file" section.
6. Ran the test for GREEN.
7. Committed the two files by name.

## RED output (after the fixture fix, before the manifest existed)

```
== manifest file exists ==
  FAIL manifest file is missing at build-conf/project-release.yaml

== reading release_version (R2) ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: open /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/read-version/project-release.yaml: no such file or directory
  FAIL reading release_version returns 1.2.0 (expected [1.2.0], got [])
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: open /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/read-version-tag/project-release.yaml: no such file or directory
  FAIL release_version reports !!str (expected [!!str], got [])

== writing release_version (R3) ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: stat /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-replaces/project-release.yaml: no such file or directory
Error: open /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-replaces/project-release.yaml: no such file or directory
  FAIL writing 1.3.0 replaces the stored version (expected [1.3.0], got [])
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: stat /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-quotes/project-release.yaml: no such file or directory
grep: /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-quotes/project-release.yaml: No such file or directory
  FAIL writing did not keep release_version double-quoted
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: stat /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-numeric-looking/project-release.yaml: no such file or directory
Error: open /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/write-numeric-looking/project-release.yaml: no such file or directory
  FAIL writing numeric-looking 1.3 reports !!str (expected [!!str], got [])

== support axis keys (R4) ==
cp: cannot stat '/workspaces/llama.cpp-rocm-docker/build-conf/project-release.yaml': No such file or directory
Error: open /workspaces/llama.cpp-rocm-docker/.tmp/release-manifest-file-tests/support-keys/project-release.yaml: no such file or directory
  FAIL support keys are llama-cpp, amd-rocm, amd-arch in order (expected [["llama-cpp","amd-rocm","amd-arch"]], got [])

== yq failure behaviour (R6) ==
  ok   reading a missing file exits 1
  ok   reading a missing file reports no such file or directory
  ok   writing a missing file exits 1
  ok   writing a missing file does not create it
  ok   reading a missing release_version key prints null
  ok   reading a missing release_version key exits 0
  ok   unquoted release_version: 1.2 reports !!float
=== 7 passed, 7 failed ===
exit=1
```

Before the fixture fix, the same run showed `FAIL` only on "manifest file is missing" and `13 passed, 1 failed`, because R2 to R4 wrote their own fixtures and never read the committed file. That is why the fixture fix was needed.

## GREEN output

```
== manifest file exists ==
  ok   manifest file exists at build-conf/project-release.yaml

== reading release_version (R2) ==
  ok   reading release_version returns 1.2.0
  ok   release_version reports !!str

== writing release_version (R3) ==
  ok   writing 1.3.0 replaces the stored version
  ok   writing keeps release_version double-quoted
  ok   writing numeric-looking 1.3 reports !!str

== support axis keys (R4) ==
  ok   support keys are llama-cpp, amd-rocm, amd-arch in order

== yq failure behaviour (R6) ==
  ok   reading a missing file exits 1
  ok   reading a missing file reports no such file or directory
  ok   writing a missing file exits 1
  ok   writing a missing file does not create it
  ok   reading a missing release_version key prints null
  ok   reading a missing release_version key exits 0
  ok   unquoted release_version: 1.2 reports !!float
=== 14 passed, 0 failed ===
exit=0
```

## Files changed

- `build-conf/project-release.yaml` (new, 9 lines): the spec's "The file" content, with `release_version: "1.2.0"` and the axes `llama-cpp`, `amd-rocm`, `amd-arch`.
- `tests/test_release_manifest_file.sh` (new, 174 lines): R1 to R4 and R6 checks. R2 to R4 fixtures are copies of the committed manifest. R6 checks use inline data. All fixtures are under `.tmp/release-manifest-file-tests/`, which is gitignored. The committed manifest is only read (via `cp`), never written.

Git status after commit: clean.

## Concerns

- The test file already existed as untracked work before I started, and I edited it. The edit was the fixture change described above, which makes R2 to R4 test the committed file rather than a copy of their own. The brief's expected RED ("read, write and keys checks fail because the manifest does not exist") only holds with this change.
- Test names say "writing ... replaces" and "keeps double-quoted", but they run `yq -i` on a fixture copy, so the committed file is never modified. That matches the brief.
- `.tmp/` in `.gitignore` covers the fixture directory, so no fixture files are staged.
- I did not run the other test suites (`test_contributing.sh` and others), because this task only touches the manifest and its own test.

Report path: /workspaces/llama.cpp-rocm-docker/.superpowers/sdd/2026-11-12-project-release-manifest/task-1-report.md
