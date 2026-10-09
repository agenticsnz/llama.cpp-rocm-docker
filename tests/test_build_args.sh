#!/usr/bin/env bash
# Tests build-rocm.sh's argument resolution without invoking docker.
# The --dry-run mode makes the ownership, collision and warning rules testable
# without paying a four-minute build per case.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
SCRIPT="$SRC/build-rocm.sh"
# Directory holding the three axis env files the build script reads.
CONF="$SRC/conf"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# expect_line <output-file> <exact line>
expect_line() {
    if grep -qxF -- "$2" "$1"; then note_pass "emits: $2"
    else note_fail "expected line: $2"; fi
}

# reject_line <output-file> <exact line>
reject_line() {
    if grep -qxF -- "$2" "$1"; then note_fail "unexpected line: $2"
    else note_pass "absent: $2"; fi
}

# expect_stderr <err-file> <substring>
expect_stderr() {
    if grep -qF -- "$2" "$1"; then note_pass "warns: $2"
    else note_fail "expected warning containing: $2"; fi
}

run_dry() {  # run_dry <out> <err> <arch> <rocm> <config> [extra args...]
    "$SCRIPT" --arch-env "$3" --rocm-env "$4" --config-env "$5" \
        --source "$SRC" "${@:6}" --dry-run >"$1" 2>"$2"
    echo $?
}

echo "== three-file happy path =="
rc=$(run_dry "$SCRATCH/o1" "$SCRATCH/e1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/o1" "--build-arg GPU_TARGET=gfx1200"
expect_line "$SCRATCH/o1" "--build-arg ROCM_BASE=rocm/dev-ubuntu-24.04:7.14.1-full"
expect_line "$SCRATCH/o1" "--build-arg ROCM_VERSION=7.14.1"
expect_line "$SCRATCH/o1" "--build-arg ROCM_CORE_DIR=/opt/rocm/core-7.14"
expect_line "$SCRATCH/o1" "--build-arg CMAKE_BUILD_TYPE=Release"
expect_line "$SCRATCH/o1" "--build-arg GGML_NATIVE=OFF"
expect_line "$SCRATCH/o1" "--build-arg GGML_CUDA_FA_QUANTS=all"
expect_line "$SCRATCH/o1" \
    "--tag 192.168.178.40:5001/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:1.0.0"
expect_line "$SCRATCH/o1" \
    "--tag 192.168.178.40:5001/agenticsnz/llama.cpp-v0.5.0-amd-7.14.1-gfx1200:latest"

echo
echo "== the deprecated all-quants key is set by no env file =="
# GGML_CUDA_FA_ALL_QUANTS is deprecated upstream: common.cmake warns that it is
# superseded by GGML_CUDA_FA_QUANTS=all and overrides it to all regardless. A file
# carrying it would put a deprecation warning in every configure log and express
# nothing that GGML_CUDA_FA_QUANTS=all does not, so none of the three may set it.
for env_file in "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env"; do
    if grep -qE '^[[:space:]]*GGML_CUDA_FA_ALL_QUANTS[[:space:]]*=' "$env_file"; then
        note_fail "$(basename "$env_file") sets the deprecated GGML_CUDA_FA_ALL_QUANTS"
    else
        note_pass "$(basename "$env_file") does not set the deprecated GGML_CUDA_FA_ALL_QUANTS"
    fi
done
# The emitted form would be "--build-arg GGML_CUDA_FA_ALL_QUANTS=<value>", so this
# is a substring test rather than reject_line's whole-line match.
if grep -q 'GGML_CUDA_FA_ALL_QUANTS' "$SCRATCH/o1"; then
    note_fail "the resolved arguments carry the deprecated GGML_CUDA_FA_ALL_QUANTS"
else
    note_pass "the resolved arguments carry no GGML_CUDA_FA_ALL_QUANTS"
fi

echo
echo "== ownership: a key in two files resolves to the owner and warns =="
# Each axis file carries a stray key belonging to the other axis. The owner's
# value must win in both directions, and each loss must be reported.
cat > "$SCRATCH/cross-arch.env" <<'ENV'
GPU_TARGET=gfx1200
ARCH_STRING=gfx1200
ROCM_BASE=rocm/dev-ubuntu-24.04:9.9.9-full
ENV
cat > "$SCRATCH/cross-rocm.env" <<'ENV'
ROCM_BASE=rocm/dev-ubuntu-24.04:7.14.1-full
ROCM_VERSION=7.14.1
ROCM_BASE_ASSEMBLY=published-multiarch-image
ROCM_CORE_DIR=/opt/rocm/core-7.14
LD_LIBRARY_PATH=/opt/rocm/lib
GPU_TARGET=gfx9999
ENV
rc=$(run_dry "$SCRATCH/o2" "$SCRATCH/e2" \
    "$SCRATCH/cross-arch.env" "$SCRATCH/cross-rocm.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0 on collision" || note_fail "exit was $rc, want 0"
# GPU_TARGET is owned by the architecture file, so gfx9999 from the version file loses
expect_line "$SCRATCH/o2" "--build-arg GPU_TARGET=gfx1200"
reject_line "$SCRATCH/o2" "--build-arg GPU_TARGET=gfx9999"
expect_stderr "$SCRATCH/e2" "GPU_TARGET"
expect_stderr "$SCRATCH/e2" "arch axis"
# ROCM_BASE is owned by the version file, so 9.9.9 from the architecture file loses
expect_line "$SCRATCH/o2" "--build-arg ROCM_BASE=rocm/dev-ubuntu-24.04:7.14.1-full"
reject_line "$SCRATCH/o2" "--build-arg ROCM_BASE=rocm/dev-ubuntu-24.04:9.9.9-full"
expect_stderr "$SCRATCH/e2" "ROCM_BASE"

echo
echo "== axis-neutral key duplicated in an axis file loses to build-config.env =="
# --config-env names the neutral file itself, so the duplicate has to be planted
# in an axis file: a stray CMAKE_BUILD_TYPE there must not win.
cat > "$SCRATCH/stray-cfg.env" <<'ENV'
GPU_TARGET=gfx1200
ARCH_STRING=gfx1200
CMAKE_BUILD_TYPE=Debug
ENV
rc=$(run_dry "$SCRATCH/o3" "$SCRATCH/e3" \
    "$SCRATCH/stray-cfg.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/o3" "--build-arg CMAKE_BUILD_TYPE=Release"
reject_line "$SCRATCH/o3" "--build-arg CMAKE_BUILD_TYPE=Debug"
expect_stderr "$SCRATCH/e3" "CMAKE_BUILD_TYPE"

echo
echo "== multi-target GPU_TARGET with a single-target filename warns, exits 0 =="
cat > "$SCRATCH/amd-gfx1200.env" <<'ENV'
GPU_TARGET=gfx1200;gfx1201
ARCH_STRING=gfx1200
ENV
rc=$(run_dry "$SCRATCH/o4" "$SCRATCH/e4" \
    "$SCRATCH/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/o4" "--build-arg GPU_TARGET=gfx1200;gfx1201"
expect_stderr "$SCRATCH/e4" "GPU_TARGET"

echo
echo "== version filename disagreeing with ROCM_VERSION warns, exits 0 =="
cat > "$SCRATCH/amd-9.9.9.env" <<'ENV'
ROCM_BASE=rocm/dev-ubuntu-24.04:9.9.9-full
ROCM_VERSION=9.9.9
ROCM_BASE_ASSEMBLY=published-multiarch-image
ROCM_CORE_DIR=/opt/rocm/core-9.9
ENV
rc=$(run_dry "$SCRATCH/o5" "$SCRATCH/e5" \
    "$CONF/amd-gfx1200.env" "$SCRATCH/amd-9.9.9.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/o5" "--build-arg ROCM_VERSION=9.9.9"

echo
echo "== ROCM_VERSION disagreeing with the tag inside ROCM_BASE warns =="
cat > "$SCRATCH/amd-7.14.1.env" <<'ENV'
ROCM_BASE=rocm/dev-ubuntu-24.04:8.8.8-full
ROCM_VERSION=7.14.1
ROCM_BASE_ASSEMBLY=published-multiarch-image
ROCM_CORE_DIR=/opt/rocm/core-7.14
LD_LIBRARY_PATH=/opt/rocm/lib
ENV
rc=$(run_dry "$SCRATCH/o6" "$SCRATCH/e6" \
    "$CONF/amd-gfx1200.env" "$SCRATCH/amd-7.14.1.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_stderr "$SCRATCH/e6" "ROCM_BASE"

echo
echo "== unknown keys pass through unchanged =="
cat > "$SCRATCH/extra-arch.env" <<'ENV'
GPU_TARGET=gfx1200
ARCH_STRING=gfx1200
SOME_FUTURE_FLAG=7
ENV
rc=$(run_dry "$SCRATCH/o7" "$SCRATCH/e7" \
    "$SCRATCH/extra-arch.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/o7" "--build-arg SOME_FUTURE_FLAG=7"

echo
echo "== missing required flag exits non-zero =="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --source "$SRC" --dry-run \
    >"$SCRATCH/o8" 2>&1
[ $? -ne 0 ] && note_pass "missing flags rejected" || note_fail "accepted a bad invocation"

echo
echo "== --set displaces a file value =="
rc=$(run_dry "$SCRATCH/s1" "$SCRATCH/se1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set ROCM_VERSION=10.1.0)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=10.1.0"
reject_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=7.14.1"
expect_stderr "$SCRATCH/se1" "ROCM_VERSION"

echo
echo "== malformed --set is fatal =="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SRC" \
    --set NOEQUALS --dry-run >"$SCRATCH/s2" 2>&1
[ $? -ne 0 ] && note_pass "bare --set rejected" || note_fail "accepted --set without ="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SRC" \
    --set =value --dry-run >"$SCRATCH/s2b" 2>&1
[ $? -ne 0 ] && note_pass "empty --set key rejected" || note_fail "accepted --set with empty key"
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SRC" \
    --dry-run --set >"$SCRATCH/s2c" 2>&1
[ $? -ne 0 ] && note_pass "trailing --set rejected" || note_fail "accepted trailing --set without value"

echo
echo "== --set keeps value after first equals and strips key whitespace =="
rc=$(run_dry "$SCRATCH/s3" "$SCRATCH/se3" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set SOME_FUTURE_FLAG=a=b --set " GPU_TARGET =gfx1200")
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s3" "--build-arg SOME_FUTURE_FLAG=a=b"
expect_line "$SCRATCH/s3" "--build-arg GPU_TARGET=gfx1200"

echo
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

echo
echo "== shell fallback adopted only when files omit a known key =="
cat > "$SCRATCH/no-registry.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
VERSION=1.0.0
CMAKE_BUILD_TYPE=Release
GGML_NATIVE=OFF
ENV
rc=$( ( export REGISTRY=shell-registry:5000
  run_dry "$SCRATCH/s5" "$SCRATCH/se5" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/no-registry.env" ) )
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s5" "--build-arg REGISTRY=shell-registry:5000"
expect_stderr "$SCRATCH/se5" "REGISTRY"

echo
echo "== files beat shell and unknown exports never leak =="
rc=$( ( export REGISTRY=shell-registry:5000 SOME_RANDOM_EXPORT=leak EMPTY_EXPORT=""
  run_dry "$SCRATCH/s6" "$SCRATCH/se6" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" ) )
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s6" "--build-arg REGISTRY=192.168.178.40:5001"
reject_line "$SCRATCH/s6" "--build-arg REGISTRY=shell-registry:5000"
if grep -q 'SOME_RANDOM_EXPORT\|EMPTY_EXPORT' "$SCRATCH/s6"; then
  note_fail "shell-only unknown keys leaked into build args"
else
  note_pass "unknown shell vars absent"
fi

echo
echo "== empty --set value behaves as absent =="
rc=$(run_dry "$SCRATCH/s7" "$SCRATCH/se7" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set SOME_FUTURE_FLAG=)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
reject_line "$SCRATCH/s7" "--build-arg SOME_FUTURE_FLAG="

echo
echo "== duplicate --set last wins without warning =="
rc=$(run_dry "$SCRATCH/s8" "$SCRATCH/se8" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    --set REGISTRY=a --set REGISTRY=b)
[ "$rc" = "0" ] && note_pass "exit 0" || note_fail "exit was $rc, want 0"
expect_line "$SCRATCH/s8" "--build-arg REGISTRY=b"
reject_line "$SCRATCH/s8" "--build-arg REGISTRY=a"

echo
echo "== docker receives flag and value as separate arguments =="
# A stub docker records one line per argv element. The script must pass
# --build-arg and KEY=VALUE as two elements: one fused '--build-arg KEY=VAL'
# element makes buildx fail with "unknown flag: --build-arg KEY".
mkdir -p "$SCRATCH/stubbin" "$SCRATCH/fakesrc/.devops"
printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "<%%s>\\n" "$a"; done >>"$STUB_LOG"\n' > "$SCRATCH/stubbin/docker"
chmod +x "$SCRATCH/stubbin/docker"
touch "$SCRATCH/fakesrc/.devops/rocm.Dockerfile"
STUB_LOG="$SCRATCH/argv.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SCRATCH/fakesrc" \
    >"$SCRATCH/o9" 2>&1
[ $? -eq 0 ] && note_pass "real invocation exits 0" || note_fail "real invocation failed"
if grep -qxF -- '<--build-arg>' "$SCRATCH/argv.log" \
    && grep -qxF -- '<ARCH_STRING=gfx1200>' "$SCRATCH/argv.log" \
    && grep -qxF -- '<--tag>' "$SCRATCH/argv.log"; then
    note_pass "flag and value arrive as separate argv elements"
else
    note_fail "flag and value are not separate argv elements"
fi
if grep -q -- '^<--build-arg .*>' "$SCRATCH/argv.log"; then
    note_fail "fused '--build-arg KEY=VAL' element passed to docker"
else
    note_pass "no fused flag elements"
fi

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
