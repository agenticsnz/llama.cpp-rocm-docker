#!/usr/bin/env bash
# Tests build-rocm.sh's argument resolution without invoking docker.
# The --dry-run mode makes the ownership, collision and warning rules testable
# without paying a four-minute build per case.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
SCRIPT="$SRC/build-rocm.sh"
# Directory holding the four axis env files the build script reads.
CONF="$SRC/conf"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH" "$SRC/.tmp/manifest-tests"' EXIT

PASS=0
FAIL=0

# Read one KEY=value assignment from a real axis file. Expectations below are
# derived from the checked-in configuration, never hardcoded: the files are
# configurable, so pinning their contents here would break on every legitimate
# config edit. Scratch-file cases stay self-contained.
conf_key() {
    sed -n "s/^$2=//p" "$CONF/$1" | head -1
}

EXPECTED_GPU_TARGET="$(conf_key amd-gfx1200.env GPU_TARGET)"
EXPECTED_ARCH_STRING="$(conf_key amd-gfx1200.env ARCH_STRING)"
EXPECTED_FA_QUANTS="$(conf_key amd-gfx1200.env GGML_CUDA_FA_QUANTS)"
EXPECTED_ROCM_BASE="$(conf_key amd-7.14.1.env ROCM_BASE)"
EXPECTED_ROCM_VERSION="$(conf_key amd-7.14.1.env ROCM_VERSION)"
EXPECTED_ROCM_CORE_DIR="$(conf_key amd-7.14.1.env ROCM_CORE_DIR)"
EXPECTED_CMAKE_BUILD_TYPE="$(conf_key build-config.env CMAKE_BUILD_TYPE)"
EXPECTED_GGML_NATIVE="$(conf_key build-config.env GGML_NATIVE)"
EXPECTED_REGISTRY="$(conf_key build-config.env REGISTRY)"
EXPECTED_LLAMA_CPP_VERSION="$(conf_key llamacpp-v0.5.0.env LLAMA_CPP_VERSION)"
# Port the version file declares for the image's server and healthcheck.
EXPECTED_LLAMA_ARG_PORT="$(conf_key llamacpp-v0.5.0.env LLAMA_ARG_PORT)"
EXPECTED_IMAGE_VERSION="$(sed -n 's/^release_version: "\(.*\)"/\1/p' "$SRC/build-conf/project-release.yaml")"
# Image reference layout mirrors build_image_reference (registry, fixed
# label root and repository, llama version, ROCm version, arch, image version).
EXPECTED_IMAGE_REF="$EXPECTED_REGISTRY/agenticsnz/llama.cpp-$EXPECTED_LLAMA_CPP_VERSION-amd-$EXPECTED_ROCM_VERSION-$EXPECTED_ARCH_STRING"

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

run_dry() {  # run_dry <out> <err> <arch> <rocm> <config> <llamacpp> [extra args...]
    "$SCRIPT" --arch-env "$3" --rocm-env "$4" --config-env "$5" \
        --llamacpp-env "$6" --source "$SRC" "${@:7}" --dry-run >"$1" 2>"$2"
    echo $?
}

echo "== four-file happy path =="
rc=$(run_dry "$SCRATCH/o1" "$SCRATCH/e1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/o1" "--build-arg GPU_TARGET=$EXPECTED_GPU_TARGET"
expect_line "$SCRATCH/o1" "--build-arg ROCM_BASE=$EXPECTED_ROCM_BASE"
expect_line "$SCRATCH/o1" "--build-arg ROCM_VERSION=$EXPECTED_ROCM_VERSION"
expect_line "$SCRATCH/o1" "--build-arg ROCM_CORE_DIR=$EXPECTED_ROCM_CORE_DIR"
expect_line "$SCRATCH/o1" "--build-arg CMAKE_BUILD_TYPE=$EXPECTED_CMAKE_BUILD_TYPE"
expect_line "$SCRATCH/o1" "--build-arg GGML_NATIVE=$EXPECTED_GGML_NATIVE"
expect_line "$SCRATCH/o1" "--build-arg GGML_CUDA_FA_QUANTS=$EXPECTED_FA_QUANTS"
expect_line "$SCRATCH/o1" "--build-arg LLAMA_CPP_VERSION=$EXPECTED_LLAMA_CPP_VERSION"
expect_line "$SCRATCH/o1" "--build-arg LLAMA_ARG_PORT=$EXPECTED_LLAMA_ARG_PORT"
expect_line "$SCRATCH/o1" \
    "--tag $EXPECTED_IMAGE_REF:$EXPECTED_IMAGE_VERSION"
expect_line "$SCRATCH/o1" \
    "--tag $EXPECTED_IMAGE_REF:latest"

echo
echo "== the deprecated all-quants key is set by no env file =="
# GGML_CUDA_FA_ALL_QUANTS is deprecated upstream: common.cmake warns that it is
# superseded by GGML_CUDA_FA_QUANTS=all and overrides it to all regardless. A file
# carrying it would put a deprecation warning in every configure log and express
# nothing that GGML_CUDA_FA_QUANTS=all does not, so none of the four may set it.
for env_file in "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    "$CONF/llamacpp-v0.5.0.env"; do
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
echo "== the llama.cpp version axis is a fourth required file =="
# Scenario: --llamacpp-env joins --arch-env, --rocm-env and --config-env as a
# required flag. An invocation naming only the original three is rejected
# rather than guessed, exactly as the existing three are.
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --source "$SRC" \
    --dry-run >"$SCRATCH/v0" 2>"$SCRATCH/ve0"
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "missing --llamacpp-env rejected"; else note_fail "accepted an invocation without --llamacpp-env"; fi
expect_stderr "$SCRATCH/ve0" "--llamacpp-env was not supplied"

echo
echo "== the version file resolves LLAMA_CPP_VERSION into the image reference =="
# Scenario: the four-file invocation resolves LLAMA_CPP_VERSION from the
# version file, and the image reference composed from it is unchanged by the
# move out of the neutral file.
rc=$(run_dry "$SCRATCH/v1" "$SCRATCH/ve1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 on the four-file invocation"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/v1" "--build-arg LLAMA_CPP_VERSION=$EXPECTED_LLAMA_CPP_VERSION"
expect_line "$SCRATCH/v1" "--tag $EXPECTED_IMAGE_REF:$EXPECTED_IMAGE_VERSION"

echo
echo "== LLAMA_CPP_VERSION lives in the version file, not the neutral file =="
# Scenario: the llama.cpp tag is owned by the version axis. The neutral file
# no longer carries it, so the two copies cannot drift apart.
if grep -qE '^[[:space:]]*LLAMA_CPP_VERSION[[:space:]]*=' "$CONF/llamacpp-v0.5.0.env"; then
    note_pass "llamacpp-v0.5.0.env carries LLAMA_CPP_VERSION"
else
    note_fail "llamacpp-v0.5.0.env does not carry LLAMA_CPP_VERSION"
fi
if grep -qE '^[[:space:]]*LLAMA_CPP_VERSION[[:space:]]*=' "$CONF/build-config.env"; then
    note_fail "build-config.env still carries LLAMA_CPP_VERSION"
else
    note_pass "build-config.env no longer carries LLAMA_CPP_VERSION"
fi

echo
echo "== a stray LLAMA_CPP_VERSION in the neutral file loses and warns =="
# Scenario: the version axis owns LLAMA_CPP_VERSION, so a copy in the neutral
# file is discarded with a warning naming the llamacpp axis.
cat > "$SCRATCH/stray-version.env" <<'ENV'
CMAKE_BUILD_TYPE=Release
REGISTRY=ghcr.io
LLAMA_CPP_VERSION=v9.9.9
VERSION=1.1.1
GGML_NATIVE=OFF
ENV
rc=$(run_dry "$SCRATCH/v2" "$SCRATCH/ve2" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/stray-version.env" \
    "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 on collision"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/v2" "--build-arg LLAMA_CPP_VERSION=$EXPECTED_LLAMA_CPP_VERSION"
reject_line "$SCRATCH/v2" "--build-arg LLAMA_CPP_VERSION=v9.9.9"
expect_stderr "$SCRATCH/ve2" "llamacpp axis"

echo
echo "== LLAMA_ARG_PORT is owned by the version axis =="
# Scenario: the listening port is version-owned, so the version file carries
# LLAMA_ARG_PORT and the neutral file does not. One value then drives both the
# server and the healthcheck.
if grep -qE '^[[:space:]]*LLAMA_ARG_PORT[[:space:]]*=' "$CONF/llamacpp-v0.5.0.env"; then
    note_pass "llamacpp-v0.5.0.env carries LLAMA_ARG_PORT"
else
    note_fail "llamacpp-v0.5.0.env does not carry LLAMA_ARG_PORT"
fi
if grep -qE '^[[:space:]]*LLAMA_ARG_PORT[[:space:]]*=' "$CONF/build-config.env"; then
    note_fail "build-config.env still carries LLAMA_ARG_PORT"
else
    note_pass "build-config.env no longer carries LLAMA_ARG_PORT"
fi

echo
echo "== a stray LLAMA_ARG_PORT in the neutral file loses and warns =="
# Scenario: the version axis owns LLAMA_ARG_PORT, so a copy in the neutral file
# is discarded with a warning naming the llamacpp axis. The emitted build
# argument is the version file's value, never the stray one.
cat > "$SCRATCH/stray-port.env" <<'ENV'
CMAKE_BUILD_TYPE=Release
REGISTRY=ghcr.io
LLAMA_ARG_PORT=9999
VERSION=1.1.1
GGML_NATIVE=OFF
ENV
rc=$(run_dry "$SCRATCH/p1" "$SCRATCH/pe1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/stray-port.env" \
    "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 on collision"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/p1" "--build-arg LLAMA_ARG_PORT=$EXPECTED_LLAMA_ARG_PORT"
reject_line "$SCRATCH/p1" "--build-arg LLAMA_ARG_PORT=9999"
expect_stderr "$SCRATCH/pe1" "llamacpp axis"

echo
echo "== CMAKE_EXTRA_ARGS resolves to the version file's copy =="
# Scenario: the pass-through for additional -D flags is owned by the version
# axis, because which extra flags a build needs is a property of the llama.cpp
# version. The neutral file's copy loses and the loss is reported.
cat > "$SCRATCH/extra-version.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
CMAKE_EXTRA_ARGS=-DNEW_VERSION_FLAG=ON
ENV
cat > "$SCRATCH/extra-neutral.env" <<'ENV'
CMAKE_BUILD_TYPE=Release
REGISTRY=ghcr.io
LLAMA_CPP_VERSION=v0.5.0
VERSION=1.1.1
GGML_NATIVE=OFF
CMAKE_EXTRA_ARGS=-DSTRAY_FLAG=ON
ENV
rc=$(run_dry "$SCRATCH/v3" "$SCRATCH/ve3" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/extra-neutral.env" \
    "$SCRATCH/extra-version.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 on collision"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/v3" "--build-arg CMAKE_EXTRA_ARGS=-DNEW_VERSION_FLAG=ON"
reject_line "$SCRATCH/v3" "--build-arg CMAKE_EXTRA_ARGS=-DSTRAY_FLAG=ON"
expect_stderr "$SCRATCH/ve3" "llamacpp axis"

echo
echo "== a Dockerfile ARG absent from KEY_AXIS passes the version-file guard =="
# Scenario: a version-specific flag is wired in by declaring an ARG in
# Dockerfile.rocm. CMAKE_BUILD_VERBOSE is such an ARG and is not an axis key,
# so the guard must accept it rather than demand an axis entry.
cat > "$SCRATCH/arg-version.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
CMAKE_BUILD_VERBOSE=--verbose
ENV
rc=$(run_dry "$SCRATCH/v4" "$SCRATCH/ve4" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" \
    "$SCRATCH/arg-version.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 with a declared ARG"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/v4" "--build-arg CMAKE_BUILD_VERBOSE=--verbose"

echo
echo "== an unknown key in the version file is fatal =="
# Scenario: docker only warns about an unknown --build-arg and carries on, so
# a typo would silently drop the setting. The guard fails fast, naming the key
# and the file. The stderr assertions are the load-bearing ones: a bad
# invocation also exits non-zero, but for the wrong reason.
cat > "$SCRATCH/typo-version.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
LLAMA_CPP_VERSIN=v0.5.0
ENV
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$SCRATCH/typo-version.env" \
    --source "$SRC" --dry-run >"$SCRATCH/v5" 2>"$SCRATCH/ve5"
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "unknown version-file key rejected"; else note_fail "accepted an unknown version-file key"; fi
expect_stderr "$SCRATCH/ve5" "LLAMA_CPP_VERSIN"
expect_stderr "$SCRATCH/ve5" "not a build argument"

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
    "$SCRATCH/cross-arch.env" "$SCRATCH/cross-rocm.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0 on collision"; else note_fail "exit was $rc, want 0"; fi
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
    "$SCRATCH/stray-cfg.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
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
    "$SCRATCH/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
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
    "$CONF/amd-gfx1200.env" "$SCRATCH/amd-9.9.9.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
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
    "$CONF/amd-gfx1200.env" "$SCRATCH/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_stderr "$SCRATCH/e6" "ROCM_BASE"

echo
echo "== unknown keys pass through unchanged =="
cat > "$SCRATCH/extra-arch.env" <<'ENV'
GPU_TARGET=gfx1200
ARCH_STRING=gfx1200
SOME_FUTURE_FLAG=7
ENV
rc=$(run_dry "$SCRATCH/o7" "$SCRATCH/e7" \
    "$SCRATCH/extra-arch.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/o7" "--build-arg SOME_FUTURE_FLAG=7"

echo
echo "== missing required flag exits non-zero =="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --source "$SRC" --dry-run \
    >"$SCRATCH/o8" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "missing flags rejected"; else note_fail "accepted a bad invocation"; fi

echo
echo "== --set displaces a file value =="
rc=$(run_dry "$SCRATCH/s1" "$SCRATCH/se1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" \
    --set ROCM_VERSION=10.1.0)
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=10.1.0"
reject_line "$SCRATCH/s1" "--build-arg ROCM_VERSION=$EXPECTED_ROCM_VERSION"
expect_stderr "$SCRATCH/se1" "ROCM_VERSION"

echo
echo "== malformed --set is fatal =="
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SRC" \
    --set NOEQUALS --dry-run >"$SCRATCH/s2" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "bare --set rejected"; else note_fail "accepted --set without ="; fi
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SRC" \
    --set =value --dry-run >"$SCRATCH/s2b" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "empty --set key rejected"; else note_fail "accepted --set with empty key"; fi
"$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SRC" \
    --dry-run --set >"$SCRATCH/s2c" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then note_pass "trailing --set rejected"; else note_fail "accepted trailing --set without value"; fi

echo
echo "== --set keeps value after first equals and strips key whitespace =="
rc=$(run_dry "$SCRATCH/s3" "$SCRATCH/se3" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" \
    --set SOME_FUTURE_FLAG=a=b --set " GPU_TARGET =gfx1200")
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
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
    "$CONF/amd-gfx1200.env" "$SCRATCH/no-version.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" \
    --set ROCM_VERSION=10.1.0)
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/s4" "--build-arg ROCM_VERSION=10.1.0"

echo
echo "== shell fallback adopted only when files omit a known key =="
cat > "$SCRATCH/no-registry.env" <<'ENV'
LLAMA_CPP_VERSION=v0.5.0
VERSION=1.0.0
CMAKE_BUILD_TYPE=Release
GGML_NATIVE=OFF
ENV
# The exports live in a subshell on purpose, so they reach only this run.
# shellcheck disable=SC2030,SC2031
rc=$( ( export REGISTRY=shell-registry:5000
  run_dry "$SCRATCH/s5" "$SCRATCH/se5" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/no-registry.env" "$CONF/llamacpp-v0.5.0.env" ) )
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/s5" "--build-arg REGISTRY=shell-registry:5000"
expect_stderr "$SCRATCH/se5" "REGISTRY"

echo
echo "== files beat shell and unknown exports never leak =="
# shellcheck disable=SC2030,SC2031
rc=$( ( export REGISTRY=shell-registry:5000 SOME_RANDOM_EXPORT=leak EMPTY_EXPORT=""
  run_dry "$SCRATCH/s6" "$SCRATCH/se6" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" ) )
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/s6" "--build-arg REGISTRY=$EXPECTED_REGISTRY"
reject_line "$SCRATCH/s6" "--build-arg REGISTRY=shell-registry:5000"
if grep -q 'SOME_RANDOM_EXPORT\|EMPTY_EXPORT' "$SCRATCH/s6"; then
  note_fail "shell-only unknown keys leaked into build args"
else
  note_pass "unknown shell vars absent"
fi

echo
echo "== empty --set value behaves as absent =="
rc=$(run_dry "$SCRATCH/s7" "$SCRATCH/se7" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" \
    --set SOME_FUTURE_FLAG=)
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
reject_line "$SCRATCH/s7" "--build-arg SOME_FUTURE_FLAG="

echo
echo "== duplicate --set last wins without warning =="
rc=$(run_dry "$SCRATCH/s8" "$SCRATCH/se8" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env" \
    --set REGISTRY=a --set REGISTRY=b)
if [ "$rc" = "0" ]; then note_pass "exit 0"; else note_fail "exit was $rc, want 0"; fi
expect_line "$SCRATCH/s8" "--build-arg REGISTRY=b"
reject_line "$SCRATCH/s8" "--build-arg REGISTRY=a"

echo
echo "== docker receives flag and value as separate arguments =="
# A stub docker records one line per argv element. The script must pass
# --build-arg and KEY=VALUE as two elements: one fused '--build-arg KEY=VAL'
# element makes buildx fail with "unknown flag: --build-arg KEY".
mkdir -p "$SCRATCH/stubbin" "$SCRATCH/fakesrc/.devops"
cat > "$SCRATCH/stubbin/docker" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf '<%s>\n' "$a"; done >>"$STUB_LOG"
STUB
chmod +x "$SCRATCH/stubbin/docker"
touch "$SCRATCH/fakesrc/.devops/rocm.Dockerfile"
STUB_LOG="$SCRATCH/argv.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SCRATCH/fakesrc" \
    >"$SCRATCH/o9" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then note_pass "real invocation exits 0"; else note_fail "real invocation failed"; fi
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
# The script builds our Dockerfile.rocm, whose ARG dialect the resolved keys
# match (ROCM_BASE, GPU_TARGET, ...). Upstream's .devops/rocm.Dockerfile speaks
# a different dialect (BASE_ROCM_DEV_CONTAINER, ROCM_DOCKER_ARCH) and must not
# receive these args: it would derive a -complete tag that does not exist.
if grep -qxF -- '<-f>' "$SCRATCH/argv.log" \
    && grep -q -- 'Dockerfile\.rocm>$' "$SCRATCH/argv.log" \
    && ! grep -q -- 'rocm\.Dockerfile' "$SCRATCH/argv.log"; then
    note_pass "docker builds our Dockerfile.rocm, not upstream's"
else
    note_fail "docker is pointed at the wrong Dockerfile"
fi

echo
echo "== --no-cache reaches docker only when requested =="
STUB_LOG="$SCRATCH/argv-nc.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SCRATCH/fakesrc" --no-cache \
    >"$SCRATCH/o10" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then note_pass "real invocation exits 0"; else note_fail "real invocation failed"; fi
if grep -qxF -- '<--no-cache>' "$SCRATCH/argv-nc.log"; then
    note_pass "--no-cache passed to docker"
else
    note_fail "--no-cache missing from docker argv"
fi
STUB_LOG="$SCRATCH/argv-c.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SCRATCH/fakesrc" \
    >"$SCRATCH/o11" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then note_pass "real invocation exits 0"; else note_fail "real invocation failed"; fi
if grep -qxF -- '<--no-cache>' "$SCRATCH/argv-c.log"; then
    note_fail "--no-cache passed without the flag"
else
    note_pass "--no-cache absent by default"
fi

echo
echo "== --verbose reaches docker and cmake only when requested =="
STUB_LOG="$SCRATCH/argv-v.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SCRATCH/fakesrc" --verbose \
    >"$SCRATCH/o12" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then note_pass "real invocation exits 0"; else note_fail "real invocation failed"; fi
if grep -qxF -- '<--progress=plain>' "$SCRATCH/argv-v.log" \
    && grep -qxF -- '<CMAKE_BUILD_VERBOSE=--verbose>' "$SCRATCH/argv-v.log"; then
    note_pass "verbose passed to docker and cmake"
else
    note_fail "verbose missing from docker/cmake argv"
fi
STUB_LOG="$SCRATCH/argv-q.log" PATH="$SCRATCH/stubbin:$PATH" \
    "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" --source "$SCRATCH/fakesrc" \
    >"$SCRATCH/o13" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then note_pass "real invocation exits 0"; else note_fail "real invocation failed"; fi
if grep -qxF -- '<--progress=plain>' "$SCRATCH/argv-q.log" \
    || grep -qxF -- '<CMAKE_BUILD_VERBOSE=--verbose>' "$SCRATCH/argv-q.log"; then
    note_fail "verbose passed without the flag"
else
    note_pass "verbose absent by default"
fi

echo
echo "== the image version comes from release_version in the manifest =="
# Scenario: the version tag is the manifest's release_version, not a build
# config value.
rc=$(run_dry "$SCRATCH/m1" "$SCRATCH/me1" \
    "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$CONF/build-config.env" "$CONF/llamacpp-v0.5.0.env")
expect_line "$SCRATCH/m1" "--tag $EXPECTED_IMAGE_REF:$EXPECTED_IMAGE_VERSION"

echo
echo "== a changed manifest version changes the tag =="
# Scenario: a copy of the tree whose manifest carries 1.3.0 tags the image 1.3.0.
MANIFEST_TREES="$SRC/.tmp/manifest-tests"
copy_tree() {  # copy_tree <name>: copies the build tree into .tmp and prints its path
    local tree="$MANIFEST_TREES/$1"
    rm -rf "$tree"
    mkdir -p "$tree"
    cp -r "$SRC/build-rocm.sh" "$SRC/Dockerfile.rocm" "$SRC/scripts" "$SRC/build-conf" "$SRC/conf" "$tree/"
    printf '%s\n' "$tree"
}
run_copy() {  # run_copy <tree> <out> <err>: dry run of a copied tree's script, prints exit status
    local tree="$1"
    "$tree/build-rocm.sh" --arch-env "$tree/conf/amd-gfx1200.env" --rocm-env "$tree/conf/amd-7.14.1.env" \
        --config-env "$tree/conf/build-config.env" --llamacpp-env "$tree/conf/llamacpp-v0.5.0.env" \
        --source "$SRC" --dry-run >"$2" 2>"$3"
    echo $?
}
TREE="$(copy_tree bump)"
sed -i 's/^release_version: .*/release_version: "1.3.0"/' "$TREE/build-conf/project-release.yaml"
run_copy "$TREE" "$SCRATCH/m2" "$SCRATCH/me2" >/dev/null
expect_line "$SCRATCH/m2" "--tag $EXPECTED_IMAGE_REF:1.3.0"

echo
echo "== a missing release_version exits non-zero =="
TREE="$(copy_tree no-version)"
sed -i '/^release_version:/d' "$TREE/build-conf/project-release.yaml"
rc=$(run_copy "$TREE" "$SCRATCH/m3" "$SCRATCH/me3")
if [ "$rc" != "0" ]; then note_pass "exit status is $rc"; else note_fail "exit was 0 without release_version"; fi

echo
echo "== a missing release_version is named in the error =="
TREE="$(copy_tree no-version-named)"
sed -i '/^release_version:/d' "$TREE/build-conf/project-release.yaml"
run_copy "$TREE" "$SCRATCH/m4" "$SCRATCH/me4" >/dev/null
expect_stderr "$SCRATCH/me4" "build-conf/project-release.yaml"

echo
echo "== a malformed release_version exits non-zero =="
TREE="$(copy_tree bad-version)"
sed -i 's/^release_version: .*/release_version: "1.2"/' "$TREE/build-conf/project-release.yaml"
rc=$(run_copy "$TREE" "$SCRATCH/m5" "$SCRATCH/me5")
if [ "$rc" != "0" ]; then note_pass "exit status is $rc"; else note_fail "exit was 0 for release_version 1.2"; fi

echo
echo "== a malformed release_version is named in the error =="
TREE="$(copy_tree bad-version-named)"
sed -i 's/^release_version: .*/release_version: "1.2"/' "$TREE/build-conf/project-release.yaml"
run_copy "$TREE" "$SCRATCH/m6" "$SCRATCH/me6" >/dev/null
expect_stderr "$SCRATCH/me6" "build-conf/project-release.yaml"

echo
echo "== an unquoted release_version is rejected =="
# Scenario: YAML reads unquoted 1.2 as a number, which must still fail the
# MAJOR.MINOR.PATCH check and name the manifest.
TREE="$(copy_tree unquoted-version)"
sed -i 's/^release_version: .*/release_version: 1.2/' "$TREE/build-conf/project-release.yaml"
rc=$(run_copy "$TREE" "$SCRATCH/m7" "$SCRATCH/me7")
if [ "$rc" != "0" ]; then note_pass "exit status is $rc"; else note_fail "exit was 0 for unquoted release_version 1.2"; fi
expect_stderr "$SCRATCH/me7" "build-conf/project-release.yaml"

echo
echo "== a missing manifest exits non-zero =="
TREE="$(copy_tree no-manifest)"
rm -f "$TREE/build-conf/project-release.yaml"
rc=$(run_copy "$TREE" "$SCRATCH/m8" "$SCRATCH/me8")
if [ "$rc" != "0" ]; then note_pass "exit status is $rc"; else note_fail "exit was 0 without the manifest"; fi

echo
echo "== a missing manifest is named in the error =="
TREE="$(copy_tree no-manifest-named)"
rm -f "$TREE/build-conf/project-release.yaml"
run_copy "$TREE" "$SCRATCH/m9" "$SCRATCH/me9" >/dev/null
expect_stderr "$SCRATCH/me9" "build-conf/project-release.yaml"

echo
echo "== a missing yq exits non-zero =="
# Scenario: with no yq on PATH the build stops before reading the manifest.
# The PATH must not hold yq, so the precondition is checked first.
if PATH=/usr/bin:/bin command -v yq >/dev/null 2>&1; then
    note_fail "yq is on /usr/bin:/bin, so the missing-yq case cannot run"
fi
PATH=/usr/bin:/bin "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" \
    --source "$SRC" --dry-run >"$SCRATCH/m10" 2>"$SCRATCH/me10"
rc=$?
if [ "$rc" != "0" ]; then note_pass "exit status is $rc"; else note_fail "exit was 0 without yq"; fi

echo
echo "== a missing yq is named in the error =="
PATH=/usr/bin:/bin "$SCRIPT" --arch-env "$CONF/amd-gfx1200.env" --rocm-env "$CONF/amd-7.14.1.env" \
    --config-env "$CONF/build-config.env" --llamacpp-env "$CONF/llamacpp-v0.5.0.env" \
    --source "$SRC" --dry-run >"$SCRATCH/m11" 2>"$SCRATCH/me11"
expect_stderr "$SCRATCH/me11" "yq"

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
