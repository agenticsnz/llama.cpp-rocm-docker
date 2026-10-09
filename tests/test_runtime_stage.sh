#!/usr/bin/env bash
# Verifies the Dockerfile's runtime stage: that it is self-contained, that the
# loader resolves every library, that the GPU is actually reported at run time, and
# that the trimming removed the other architectures' kernels without removing this
# one's.
#
# The device check runs against the real GPU. Everything else in this project that
# checks the image by inspection can pass on an image with no compute device at
# all, because the container still starts, amd-smi still reports the card and the
# healthcheck still returns 200. `llama-server --list-devices` is the check that
# distinguishes those two images, so it is not optional here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"
DOCKERFILE="$PROJECT_ROOT/Dockerfile.rocm"
BUILD_LOG="$HERE/../runtime-stage.log"

# Pinned so the check compares like with like between runs.
readonly TEST_IMAGE='llamacpp-rocm-runtime-check:latest'
readonly LLAMA_CPP_TAG='v0.5.0'
readonly LLAMA_CPP_REPOSITORY='https://github.com/ggml-org/llama.cpp.git'
readonly ROCM_BASE="${ROCM_BASE:-rocm/dev-ubuntu-24.04:7.14.1-full}"
readonly ROCM_CORE_DIR="${ROCM_CORE_DIR:-/opt/rocm/core-7.14}"
readonly GPU_TARGET="${GPU_TARGET:-gfx1200}"
readonly UPSTREAM_DOCKERFILE_PATH='.devops/rocm.Dockerfile'

# The size ceiling. The trimmed ROCm tree measures about 1211 MB and the
# application about 110 MB, so a correct image lands far below this; the ceiling
# exists to catch a regression to copying the whole multi-architecture base, not to
# police the last few megabytes.
readonly MAX_IMAGE_BYTES=$((12 * 1000 * 1000 * 1000))

# The architectures whose kernels the trimming must remove. Sampled rather than
# exhaustive: gfx90a and gfx942 are the two largest other-architecture trees by a
# wide margin, and gfx1201 is the closest sibling to this card, so a filter keyed
# on a prefix that was too greedy would catch it.
readonly OTHER_ARCHITECTURES='gfx908 gfx90a gfx942 gfx1100 gfx1151 gfx1201'

# The loader registration the base image does not provide.
readonly LOADER_CONFIG='/etc/ld.so.conf.d/rocm.conf'

# The tool tree Part 2 owns. Asserting it is absent keeps the boundary between the
# two specs clean rather than letting a tool appear here unnoticed.
readonly PART2_TOOL_NAMES='bench-model test-model add-model'

readonly LLAMA_CPP_CACHE_DIR="$PROJECT_ROOT/.tmp"
readonly LLAMA_CPP_SOURCE_DIR="$LLAMA_CPP_CACHE_DIR/llama-cpp-$LLAMA_CPP_TAG"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# Run a command in a container from the runtime image. Used for the checks that do
# not need the GPU; the ones that do pass the device flags explicitly.
in_image() {
    docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" -c "$1" 2>&1
}

# Run a command in a container with the GPU attached, which is how the device
# checks are made. LD_LIBRARY_PATH is deliberately not set: the image is required
# to be self-contained, so a device that only appears when the variable is
# supplied would fail this.
in_image_with_gpu() {
    docker run --rm --runtime amd --device /dev/kfd --device /dev/dri \
        --entrypoint /bin/bash "$TEST_IMAGE" -c "$1" 2>&1
}

report_cached_source_if_present() {
    if [ ! -d "$LLAMA_CPP_SOURCE_DIR/.git" ]; then
        return 1
    fi
    if [ ! -f "$LLAMA_CPP_SOURCE_DIR/$UPSTREAM_DOCKERFILE_PATH" ]; then
        printf 'removing the cached tree at %s: it has no %s, so it is not the pinned checkout.\n' \
            "$LLAMA_CPP_SOURCE_DIR" "$UPSTREAM_DOCKERFILE_PATH"
        rm -rf "$LLAMA_CPP_SOURCE_DIR"
        return 1
    fi
    return 0
}

prepare_source_context() {
    report_cached_source_if_present && return 0
    printf 'fetching llama.cpp %s (this happens once; later runs reuse the cache)...\n' "$LLAMA_CPP_TAG"
    git clone --depth 1 --branch "$LLAMA_CPP_TAG" \
        "$LLAMA_CPP_REPOSITORY" "$LLAMA_CPP_SOURCE_DIR" >/dev/null 2>&1 || {
        printf 'FAIL could not fetch llama.cpp %s. The build context is a llama.cpp tree, so the check cannot run without it.\n' \
            "$LLAMA_CPP_TAG"
        return 1
    }
    report_cached_source_if_present
}

if [ ! -f "$DOCKERFILE" ]; then
    printf 'FAIL %s does not exist.\n' "$DOCKERFILE"
    exit 1
fi

prepare_source_context || exit 1

# The build stage is already cached from the Task 2 check, so building the runtime
# target on top of it is cheap; the whole build still takes a few minutes.
printf 'building the runtime stage (the build stage is cached)...\n'
if ! nice -n 19 ionice -c 3 docker build --progress=plain --target runtime \
        --build-arg "ROCM_BASE=$ROCM_BASE" \
        --build-arg "ROCM_CORE_DIR=$ROCM_CORE_DIR" \
        --build-arg "GPU_TARGET=$GPU_TARGET" \
        -f "$DOCKERFILE" -t "$TEST_IMAGE" "$LLAMA_CPP_SOURCE_DIR" \
        > "$BUILD_LOG" 2>&1; then
    printf 'FAIL the runtime stage did not build. Last 20 lines of %s:\n' "$BUILD_LOG"
    tail -20 "$BUILD_LOG"
    exit 1
fi
note_pass "runtime stage built"

# ---- size -------------------------------------------------------------------

image_size="$(docker image inspect "$TEST_IMAGE" --format '{{.Size}}')"
if [ "$image_size" -lt "$MAX_IMAGE_BYTES" ]; then
    note_pass "image is $((image_size / 1000000)) MB, under the 12 GB ceiling"
else
    note_fail "image is $((image_size / 1000000)) MB, at or over the 12 GB ceiling"
fi

# ---- loader -----------------------------------------------------------------

if in_image "test -f '$LOADER_CONFIG'"; then
    note_pass "$LOADER_CONFIG exists"
else
    note_fail "$LOADER_CONFIG is absent; ldconfig was never told where ROCm is"
fi

if in_image "grep -q '/opt/rocm/lib' '$LOADER_CONFIG'"; then
    note_pass "the loader is pointed at /opt/rocm/lib"
else
    note_fail "the loader is not pointed at /opt/rocm/lib"
fi

# Every library the backend needs must resolve. This is the assertion that turns
# the silent no-device failure into a loud one, so it is checked in the image
# rather than trusted to the Dockerfile's own build-time check.
unresolved_hip="$(in_image "ldd /app/libggml-hip.so | grep 'not found' || true")"
if [ -z "$unresolved_hip" ]; then
    note_pass "ldd /app/libggml-hip.so resolves every library"
else
    note_fail "ldd /app/libggml-hip.so has unresolved libraries:"
    printf '%s\n' "$unresolved_hip" | sed 's/^/         /'
fi

unresolved_server="$(in_image "ldd /app/llama-server | grep 'not found' || true")"
if [ -z "$unresolved_server" ]; then
    note_pass "ldd /app/llama-server resolves every library"
else
    note_fail "ldd /app/llama-server has unresolved libraries:"
    printf '%s\n' "$unresolved_server" | sed 's/^/         /'
fi

for required_library in libamdhip64 librocblas libhipblas; do
    if in_image "ldd /app/libggml-hip.so | grep -q '$required_library'"; then
        note_pass "ldd names $required_library"
    else
        note_fail "ldd does not name $required_library"
    fi
done

# ---- the device ------------------------------------------------------------

# The check this whole stage exists to make. It runs with no LD_LIBRARY_PATH in
# the environment, so a device that only appears when the variable is supplied
# fails here, which is what "self-contained" has to mean.
device_report="$(in_image_with_gpu '/app/llama-server --list-devices 2>&1' || true)"
if printf '%s' "$device_report" | grep -q 'ROCm0'; then
    note_pass "llama-server reports a ROCm device without LD_LIBRARY_PATH set"
else
    note_fail "llama-server did not report a ROCm device. Output was:"
    printf '%s\n' "$device_report" | tail -5 | sed 's/^/         /'
fi

# A device name as well as the ROCm0 index: ROCm0 alone would also match a line
# reporting a device that then failed to initialise.
if printf '%s' "$device_report" | grep -qE 'ROCm0: .+[0-9]+ MiB'; then
    note_pass "the reported device carries a name and a memory total"
else
    note_fail "the reported device line carries no name and memory total"
fi

# ---- trimming --------------------------------------------------------------

# The kernels for this card must be present, at the paths the libraries resolve
# through. rocBLAS looks for its kernels relative to itself and hipBLASLt keeps
# them in a per-architecture subdirectory, so the layout is part of correctness
# rather than tidiness.
if in_image "find /opt/rocm -path '*rocblas*' -name '*${GPU_TARGET}*' | head -1 | grep -q ."; then
    note_pass "rocBLAS kernels for $GPU_TARGET are present"
else
    note_fail "no rocBLAS kernels for $GPU_TARGET"
fi

if in_image "test -d /opt/rocm/lib/hipblaslt/library/$GPU_TARGET"; then
    note_pass "the hipBLASLt $GPU_TARGET kernel directory is present"
else
    note_fail "the hipBLASLt $GPU_TARGET kernel directory is absent"
fi

# The other architectures' kernels are what the trimming exists to remove, so
# their absence is the assertion. Zero matches expected for each.
for other_architecture in $OTHER_ARCHITECTURES; do
    remaining="$(in_image "find /opt/rocm -name '*${other_architecture}*' | wc -l | tr -d '[:space:]'")"
    if [ "${remaining:-1}" -eq 0 ]; then
        note_pass "no $other_architecture kernels remain"
    else
        note_fail "$remaining $other_architecture kernels remain; the trim did not remove them"
    fi
done

# ---- boundary --------------------------------------------------------------

# Part 2 of the design owns the tool tree. Asserting it is absent keeps the two
# specs' boundary visible rather than letting a tool land here unnoticed.
for tool_name in $PART2_TOOL_NAMES; do
    if in_image "test -e /app/$tool_name || command -v $tool_name >/dev/null 2>&1"; then
        note_fail "$tool_name is present; Part 2 owns the tool tree"
    else
        note_pass "$tool_name is absent, as Part 2 requires"
    fi
done

if in_image "test -e /app/scripts || test -d /opt/rocm/share/rocm_docs"; then
    note_fail "the runtime stage carries a tool tree that Part 2 should add"
else
    note_pass "no Part 2 tool tree is installed"
fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
