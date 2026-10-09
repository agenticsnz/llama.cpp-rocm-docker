# build-rocm.sh `--set` Overrides Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repeatable `--set KEY=VALUE` CLI overrides and known-key shell-environment fallback to `build-rocm.sh`, with `--set` > axis files > shell env precedence.

**Architecture:** Two new pieces in `build-rocm.sh`, both plain bash following existing helpers (`die`/`warn`, `FILE_VALUE`/`RESOLVED_VALUE` maps): argument collection during parsing, then a resolution step between `apply_ownership` and `require_keys_present`. Tests extend `tests/test_build_args.sh` via its existing `expect_line`/`expect_stderr` helpers.

**Tech Stack:** Bash (`set -uo pipefail`), existing `--dry-run` harness, no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-09-build-rocm-set-overrides-design.md`

## Global Constraints

- One logical change per commit, no `Co-Authored-By` or attribution lines.
- `bash -n` clean on every touched script.
- `tests/test_build_args.sh` stays fully green (currently 36/36).
- Heavy docker-build tests (`test_build_stage.sh`, `test_runtime_stage.sh`) untouched.

## Review Focus

- `--set FOO=a=b` keeps everything after the first `=` (`a=b`) — pinned in Task 1 tests.
- `--set FOO=` (empty value) stores empty, which downstream `[ -n ]` checks treat as absent, same as an empty file value — pinned in Task 2 tests.
- `--set " GPU_TARGET =x"` strips key whitespace like file parsing — pinned in Task 1 tests.
- Exported-but-empty shell variable counts as unset and is never adopted — pinned in Task 2 tests.
- Unknown exported variables (e.g. `SOME_RANDOM_EXPORT`) never appear in `--build-arg` output — pinned in Task 2 tests.

---

### Task 1: `--set` parsing, validation, usage

**Files:**
- Modify: `build-rocm.sh` (usage line, `parse_arguments`, new `CLI_VALUE` map)
- Test: `tests/test_build_args.sh` (`run_dry` gains extra-args passthrough, new cases)

**Interfaces:**
- Consumes: existing `die`, `USAGE_MESSAGE`, `parse_arguments` flag loop.
- Produces: `declare -A CLI_VALUE` (keyed by key, last `--set` wins) populated before `main` resolves paths; updated `USAGE_MESSAGE` containing `--set KEY=VALUE`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_build_args.sh`, extend the runner to pass extra args through (inserted before `--dry-run`):

```bash
run_dry() {  # run_dry <out> <err> <arch> <rocm> <config> [extra args...]
    "$SCRIPT" --arch-env "$3" --rocm-env "$4" --config-env "$5" \
        --source "$SRC" "${@:6}" --dry-run >"$1" 2>"$2"
    echo $?
}
```

New cases (all existing cases keep passing unchanged):

```bash
echo "== --set displaces a file value =="
rc=$(run_dry "$SCRATCH/s1" "$SCRATCH/se1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set ROCM_VERSION=10.1.0)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=10.1.0"
reject_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=7.14.1"
expect_stderr "$SCRATCH/se1" "ROCM_VERSION"
```

```bash
echo "== malformed --set is fatal =="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SRC" \
    --set NOEQUALS --dry-run >"$SCRATCH/s2" 2>&1
[ $? -ne 0 ] && note_pass "bare --set rejected" || note_fail "accepted --set without ="
```

Value keeps everything after the first `=`, key whitespace stripped:

```bash
rc=$(run_dry "$SCRATCH/s3" "$SCRATCH/se3" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set SOME_FUTURE_FLAG=a=b " GPU_TARGET =gfx1200")
expect_line "$SCRATCH/s3" "--build-arg SOME_FUTURE_FLAG=a=b"
expect_line "$SCRATCH/s3" "--build-arg GPU_TARGET=gfx1200"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_build_args.sh`
Expected: FAIL on the three new cases (`--set` unrecognized argument; `run_dry` ignores extras). All 36 existing assertions still pass.

- [ ] **Step 3: Implement `--set` parsing in `build-rocm.sh`**

Add `declare -A CLI_VALUE=()` next to `FILE_VALUE`. In `parse_arguments`, add a `--set` branch before the existing flag group: require a following argument (else `die`), require it to contain `=` (else `die` naming the offending value), split at the first `=`, strip all whitespace from the key only (same `${key//[[:space:]]/}` idiom as file loading), reject empty keys via `die`, store (overwrite = last wins). Use `${var:-}` forms throughout so `set -u` never fires. Append `[--set KEY=VALUE ...]` to `USAGE_MESSAGE`.

- [ ] **Step 4: Run tests to verify new cases pass and nothing regressed**

Run: `bash tests/test_build_args.sh`
Expected: all green including the 3 new cases. Run: `bash -n build-rocm.sh tests/test_build_args.sh`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add build-rocm.sh tests/test_build_args.sh
git commit -m "Parse repeatable --set KEY=VALUE overrides in build-rocm.sh"
```

### Task 2: Resolution precedence (`--set` > files > shell env)

**Files:**
- Modify: `build-rocm.sh` (`apply_cli_overrides` + shell fallback, wired into `main`)
- Test: `tests/test_build_args.sh` (new cases)

**Interfaces:**
- Consumes: `CLI_VALUE` from Task 1; `RESOLVED_VALUE`, `REQUIRED_KEYS`, `KEY_AXIS`, `warn`, `apply_ownership`.
- Produces: final `RESOLVED_VALUE` honoring CLI > files > shell env; `--set` able to satisfy `REQUIRED_KEYS`.

- [ ] **Step 1: Write the failing tests**

```bash
echo "== --set satisfies a missing required key =="
cat > "$SCRATCH/no-version.env" <<'ENV'
ROCM_BASE=rocm/dev-ubuntu-24.04:10.1.0-full
ROCM_BASE_ASSEMBLY=published-multiarch-image
ROCM_CORE_DIR=/opt/rocm/core-10.1
LD_LIBRARY_PATH=/opt/rocm/lib
ENV
rc=$(run_dry "$SCRATCH/s4" "$SCRATCH/se4" \
    "$CONF/amd-gfx1200.env" "$SCRATCH/no-version.env" "$CONF/build-config.env" \
    --set ROCM_VERSION=10.1.0)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s4" "--build-arg ROCM_VERSION=10.1.0"
```

```bash
echo "== shell fallback adopted only when files omit a known key =="
cat > "$SCRATCH/no-registry.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
VERSION=1.0.0
CMAKE_BUILD_TYPE=Release
GGML_NATIVE=OFF
ENV
```bash
rc=$( ( export REGISTRY=shell-registry:5000
  run_dry "$SCRATCH/s5" "$SCRATCH/se5" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/no-registry.env" ) )
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s5" "--build-arg REGISTRY=shell-registry:5000"
expect_stderr "$SCRATCH/se5" "REGISTRY"
```

Files beat shell, empty export counts as unset, unknown exports never leak:

```bash
rc=$( ( export REGISTRY=shell-registry:5000 SOME_RANDOM_EXPORT=leak EMPTY_EXPORT=""
  run_dry "$SCRATCH/s6" "$SCRATCH/se6" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" ) )
expect_line "$SCRATCH/s6" "--build-arg REGISTRY=192.168.178.40:5001"
reject_line "$SCRATCH/s6" "--build-arg REGISTRY=shell-registry:5000"
if grep -q 'SOME_RANDOM_EXPORT\|EMPTY_EXPORT' "$SCRATCH/s6"; then
  note_fail "shell-only unknown keys leaked into build args"
else
  note_pass "unknown shell vars absent"
fi
```

Empty `--set` value behaves as absent:

```bash
rc=$(run_dry "$SCRATCH/s7" "$SCRATCH/se7" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set SOME_FUTURE_FLAG=)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
reject_line "$SCRATCH/s7" "--build-arg SOME_FUTURE_FLAG="
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_build_args.sh`
Expected: FAIL on the new Task 2 cases (`--set` parsed but never applied; `no-version.env` dies on missing `ROCM_VERSION`; shell fallback absent). Task 1 cases still pass.

- [ ] **Step 3: Implement resolution in `build-rocm.sh`**

Add `apply_shell_fallback` (before CLI overrides): for each key in the union of `REQUIRED_KEYS` and `${!KEY_AXIS[@]}`, if `RESOLVED_VALUE[$key]` is empty and an exported variable of that name is non-empty (`[ -n "${!key:-}" ]` via indirect expansion with `:-` default for `set -u`), adopt it and `warn` it came from the environment. Add `apply_cli_overrides` (after fallback): for each key in `CLI_VALUE`, if `RESOLVED_VALUE[$key]` is set and differs, `warn` naming the key, the displaced file value's origin, and that the CLI value wins; then assign. Wire into `main` as `apply_ownership` → `apply_shell_fallback` → `apply_cli_overrides` → `require_keys_present`.

- [ ] **Step 4: Run tests to verify everything passes**

Run: `bash tests/test_build_args.sh`
Expected: fully green (36 existing + 3 Task 1 + 5 Task 2). Run: `bash -n build-rocm.sh tests/test_build_args.sh`
Expected: clean. Also run a real `--dry-run` with `--set ROCM_VERSION=10.1.0` against the repo conf files and eyeball the warning + emitted args.

- [ ] **Step 5: Commit**

```bash
git add build-rocm.sh tests/test_build_args.sh
git commit -m "Resolve --set over files over shell env in build-rocm.sh"
```
