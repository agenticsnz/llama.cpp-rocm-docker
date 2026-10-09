# build-rocm.sh `--set` Overrides — Design

**Date:** 2026-10-09
**Status:** Awaiting review
**Scope:** `build-rocm.sh` only. No Dockerfile, `.env`, Compose, or image changes.
Decisions below were agreed in brainstorming on 2026-10-09: override spelling is
repeatable `--set KEY=VALUE`; precedence is CLI > axis files > shell environment.

## Goal

Override individual build properties from the `build-rocm.sh` command line
without editing the three axis files, e.g. test a new `ROCM_VERSION` before a
version file exists for it. `.env` files keep overriding same-named shell
variables; `--set` overrides everything.

## Context

`build-rocm.sh` resolves every key from exactly three files (`--arch-env`,
`--rocm-env`, `--config-env`) via per-axis ownership (`KEY_AXIS`), warns on
cross-axis duplicates, fails on missing `REQUIRED_KEYS`, and supports
`--dry-run` for cheap verification (`tests/test_build_args.sh`, 36/36 green).
It currently ignores the shell environment entirely. Keys unknown to
`KEY_AXIS` pass through as neutral, and `emit_resolved_arguments` emits every
resolved key as `--build-arg`, so a new override key needs no Dockerfile
change to reach `docker build`.

## Non-goals

- No `--override-file` mode and no per-key flags (e.g. `--rocm-version`).
- No change to ownership rules *between* the three files.
- No whole-environment sweep: the script never turns arbitrary exported
  variables into `--build-arg`s.
- No Dockerfile, `.env`, Compose, test-heavy (docker build), or docs changes
  beyond the script's own usage text.

## CLI syntax

    build-rocm.sh --arch-env <path> --rocm-env <path> --config-env <path> \
        --source <path> [--set KEY=VALUE ...] [--dry-run]

- `--set` is repeatable; later occurrences of the same key win (last wins).
- `KEY` must be non-empty after whitespace stripping; the argument must contain
  `=`. A missing `=`, an empty key, or a missing value argument is fatal
  (exit 2 via `die`), consistent with other bad invocations.
- Values keep everything after the first `=` verbatim, including further `=`
  signs and leading/trailing spaces, matching file parsing.
- `USAGE_MESSAGE` gains `[--set KEY=VALUE ...]`.

## Resolution order

Highest to lowest: `--set` CLI > owning axis file (existing ownership,
unchanged) > exported shell variable (fallback, known keys only, see below).

New step `apply_cli_overrides` runs after `apply_ownership`, before
`require_keys_present`:

1. For each `--set` key: if files resolved a *different* value, `warn` naming
   the key, the losing file(s), and that the CLI value wins (same voice as the
   existing ownership warning). Identical values stay silent.
2. Previously unseen keys pass through into `RESOLVED_VALUE` unchanged.
3. Duplicate `--set` for one key: last wins, no warning (explicit repetition is
   not a stray duplicate).

Shell fallback runs between file resolution and CLI overrides (equivalently:
lowest precedence). For each key in the union of `REQUIRED_KEYS` and `KEY_AXIS`
keys that no file set, if an exported shell variable of that name is
non-empty, adopt it and warn that it came from the environment (visibility,
consistent with existing warnings). Unknown keys are never read from the
environment; `--set` is their route. Empty-string exports count as unset.

Consequences, all intended:

- `--set` can satisfy `REQUIRED_KEYS` (e.g. try a version with no version file).
- `run_consistency_checks` (filename/tag warnings), `build_image_reference`,
  and emitted `--tag`/`--build-arg` lines operate on the final map unchanged.
- `--dry-run` shows the fully resolved CLI-influenced output, so overrides are
  testable without a build.

## Examples

Override the version file for a trial build:

    build-rocm.sh --arch-env conf/amd-gfx1200.env \
        --rocm-env conf/amd-7.14.1.env --config-env conf/build-config.env \
        --source ~/llama.cpp --dry-run \
        --set ROCM_BASE=rocm/dev-ubuntu-24.04:10.1.0-full \
        --set ROCM_VERSION=10.1.0 \
        --set ROCM_CORE_DIR=/opt/rocm/core-10.1

Expect warnings that each `--set` key displaced the version file's value, plus
the existing base-tag check against the overridden pair. Fill a neutral value
without touching files:

    --set REGISTRY=localhost:5001

## Testing

Extend `tests/test_build_args.sh` following its existing helpers (note:
`run_dry` will need an extra-args parameter or a second runner for `--set`):

1. `--set` displaces a file value, emits the CLI value, warns naming key+file.
2. `--set` for an absent key passes through as `--build-arg`.
3. `--set` satisfies a missing required key (drop a required key from scratch
   files, supply via `--set`, expect exit 0).
4. Malformed `--set` (no `=`, empty key) exits non-zero.
5. Shell fallback: known key absent from all files but exported in the test's
   environment is adopted (with warning); same key set in a file wins over the
   export; unknown exported variables never appear in output.
6. Full suite stays green; `bash -n` clean.

Heavy docker-build tests are untouched.
