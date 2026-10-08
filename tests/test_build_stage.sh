#!/usr/bin/env bash
# Verifies the Dockerfile build stage: that it compiles llama.cpp's HIP backend
# for the requested architecture, resolves the library closure, and produces the
# two artefacts the runtime stage consumes.
#
# The build takes minutes, so this performs one build and then asserts against
# it, rather than building per assertion.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"
DOCKERFILE="$PROJECT_ROOT/Dockerfile.rocm"
BUILD_LOG="$HERE/../build-stage.log"

# Pinned so the check compares like with like between runs. The tag is the
# contract, so a run against a different source tree would not be the same check.
readonly TEST_IMAGE='llamacpp-build-stage-check:latest'
readonly LLAMA_CPP_TAG='v0.5.0'
readonly LLAMA_CPP_REPOSITORY='https://github.com/ggml-org/llama.cpp.git'
readonly ROCM_BASE='rocm/dev-ubuntu-24.04:7.14.1-full'
readonly ROCM_CORE_DIR='/opt/rocm/core-7.14'
readonly GPU_TARGET='gfx1200'
readonly EXPECTED_ROCM_PREFIX='7.14'
readonly EXPECTED_HIPBLAS_MARKER='HIP and hipBLAS found'
readonly EXPECTED_FA_MARKER='FlashAttention K-V type combinations'

# The K/V types upstream supports, copied from FA_TYPES in
# ggml/cmake/common.cmake. The expected set is built from this list rather than
# written out, because the cross-product is 49 entries and because this list is
# what upstream would validate against: an entry naming a type outside it is a
# FATAL_ERROR at configure.
readonly FA_TYPES='q4_0 q4_1 q5_0 q5_1 q8_0 bf16 f16'

# The value the architecture env file asks for. `all` is the complete
# cross-product of the types above, which is 49 combinations; a narrowed list
# would name a subset explicitly instead.
readonly EXPECTED_FA_COMBINATION='all'

# Build the expected combination set the way upstream's CMake does: for each V
# type, every K type, producing "<type_K>-<type_V>". Sorted, so the comparison
# against the build's own ordering-independent set is a plain string match.
build_expected_fa_set() {
    local value_type key_type
    for value_type in $FA_TYPES; do
        for key_type in $FA_TYPES; do
            printf '%s-%s\n' "$key_type" "$value_type"
        done
    done | sort | tr '\n' ' ' | sed 's/ $//'
}

readonly EXPECTED_FA_COMBINATIONS="$(build_expected_fa_set)"
readonly EXPECTED_FA_SET="$EXPECTED_FA_COMBINATIONS"

# The combination upstream seeds unconditionally, before applying the caller's
# list, and which is therefore present even under a narrowed list. It is
# load-bearing: fattn.cu uses it as the fallback for any K/V type with no
# compiled vector kernel, behind a GGML_ASSERT that aborts rather than degrades.
readonly UPSTREAM_SEEDED_FA_COMBINATION='f16-f16'

# A value that must never appear, as a guard on the parsing rather than on the
# build: a combination naming a type outside FA_TYPES is a FATAL_ERROR at
# configure, so reaching a completed build already proves the list parsed. This
# asserts the narrower point that no unrequested type slipped in.
readonly UNKNOWN_FA_COMBINATION='q9_9-q9_9'
readonly CLOSURE_FILE='/opt/closure/paths.txt'
readonly UPSTREAM_DOCKERFILE_PATH='.devops/rocm.Dockerfile'

# The configure output the build writes inside the image, rather than the build
# log on the host. A cached rebuild prints no configure output to the build log,
# so assertions read from there would report on Docker's cache state rather than
# on the build. The file is part of the layer, so it is present either way.
readonly CONFIGURE_LOG='/src/configure.log'

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# The Dockerfile copies the whole context and expects a llama.cpp tree, this
# repository is not one, so the check supplies the same pinned source tree the
# build script takes as its --source argument. The tree is cached under the
# workspace's scratch directory so repeated runs do not re-download it.
readonly LLAMA_CPP_CACHE_DIR="$PROJECT_ROOT/.tmp"
readonly LLAMA_CPP_SOURCE_DIR="$LLAMA_CPP_CACHE_DIR/llama-cpp-$LLAMA_CPP_TAG"

# Report a checkout of the pinned tag when one is already present, so a repeated
# run reuses it. A cached tree missing the upstream Dockerfile is not usable as a
# context, and is reported so the caller re-clones rather than building garbage.
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
    printf 'using the cached %s tree at %s.\n' "$LLAMA_CPP_TAG" "$LLAMA_CPP_SOURCE_DIR"
    return 0
}

# Clone the pinned tag into the scratch cache. A shallow clone of the one tag is
# what keeps this cheap; the depth is the tag's own history, not the branch head.
clone_pinned_source() {
    mkdir -p "$LLAMA_CPP_CACHE_DIR" || return 1
    git clone --depth 1 --branch "$LLAMA_CPP_TAG" \
        "$LLAMA_CPP_REPOSITORY" "$LLAMA_CPP_SOURCE_DIR"
}

# Make the pinned source tree available, cloning it only when it is not cached.
prepare_source_context() {
    report_cached_source_if_present && return 0
    printf 'fetching llama.cpp %s (this happens once; later runs reuse the cache)...\n' "$LLAMA_CPP_TAG"
    clone_pinned_source >/dev/null 2>&1 || {
        printf 'FAIL could not fetch llama.cpp %s from %s. The build context is a llama.cpp tree, so the check cannot run without it.\n' \
            "$LLAMA_CPP_TAG" "$LLAMA_CPP_REPOSITORY"
        return 1
    }
    report_cached_source_if_present
}

if [ ! -f "$DOCKERFILE" ]; then
    printf 'FAIL %s does not exist. The build stage is what this check verifies.\n' "$DOCKERFILE"
    exit 1
fi

prepare_source_context || exit 1

# Build only the build stage, so this check does not depend on the runtime stage
# a later task adds.
printf 'building the build stage (several minutes)...\n'
if ! nice -n 19 ionice -c 3 docker build --progress=plain --target build \
        --build-arg "ROCM_BASE=$ROCM_BASE" \
        --build-arg "ROCM_CORE_DIR=$ROCM_CORE_DIR" \
        --build-arg "GPU_TARGET=$GPU_TARGET" \
        -f "$DOCKERFILE" -t "$TEST_IMAGE" "$LLAMA_CPP_SOURCE_DIR" \
        > "$BUILD_LOG" 2>&1; then
    printf 'FAIL the build stage did not build. Last 20 lines of %s:\n' "$BUILD_LOG"
    tail -20 "$BUILD_LOG"
    exit 1
fi
note_pass "build stage built"

# Read the configure output the build wrote inside the image, rather than the
# build log on the host. Docker prints a cached step as CACHED with no output, so
# a host-side log assertion passes or fails on cache state instead of on the
# build; the in-image file is part of the layer and is present either way.
configure_log_contents() {
    docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" -c "cat '$CONFIGURE_LOG'" 2>/dev/null
}

CONFIGURE_OUTPUT="$(configure_log_contents)"

# The configure step must have found the HIP toolchain and narrowed the
# FlashAttention K/V coverage, since both arrive as build arguments from the
# configuration files.
if printf '%s' "$CONFIGURE_OUTPUT" | grep -qF "$EXPECTED_HIPBLAS_MARKER"; then
    note_pass "configure found the HIP toolchain"
else
    note_fail "configure did not report '$EXPECTED_HIPBLAS_MARKER'"
fi

if printf '%s' "$CONFIGURE_OUTPUT" | grep -qF "$EXPECTED_FA_MARKER"; then
    note_pass "configure reported FlashAttention K/V coverage"
    fa_line="$(printf '%s' "$CONFIGURE_OUTPUT" | grep -F "$EXPECTED_FA_MARKER" | tail -1)"

    # Compare the reported combinations as a set, because the build's list order
    # is an implementation detail of upstream's CMake rather than a contract.
    # A substring test would pass a list that carried extra combinations.
    fa_combinations="$(printf '%s' "$fa_line" | sed 's/.*combinations:[[:space:]]*//' | tr ';' ' ')"
    fa_combinations="$(printf '%s\n' $fa_combinations | sort -u | tr '\n' ' ' | sed 's/ $//')"

    # The exact-set comparison is the assertion. With `all` there are 49 entries,
    # so iterating them one by one would bury the result in 49 lines that all say
    # the same thing; the count and the set together identify any discrepancy.
    if [ "$fa_combinations" = "$EXPECTED_FA_SET" ]; then
        note_pass "K/V coverage is exactly the $(printf '%s\n' $EXPECTED_FA_COMBINATIONS | wc -l | tr -d '[:space:]') combinations of '$FA_TYPES'"
    else
        note_fail "K/V coverage is '$fa_combinations', expected the 49 combinations of '$FA_TYPES'"
    fi

    # f16-f16 is present under `all` for two independent reasons: it is one of the
    # 49, and upstream seeds it unconditionally. Asserting it separately is what
    # carries the property forward to a narrowed list, where the seed is the only
    # reason it would be there. It is load-bearing either way: fattn.cu falls back
    # to it for a K/V type with no compiled vector kernel, behind a GGML_ASSERT.
    if printf '%s' "$fa_combinations" | grep -qwF "$UPSTREAM_SEEDED_FA_COMBINATION"; then
        note_pass "f16-f16 is present, which is what keeps the fattn.cu fallback from aborting"
    else
        note_fail "f16-f16 is absent; the fattn.cu fallback would abort rather than degrade"
    fi

    # A combination naming a type outside upstream's FA_TYPES is a FATAL_ERROR at
    # configure time, so reaching a completed build already proves the list
    # parsed. This asserts the narrower point that no unrequested type slipped in.
    if printf '%s' "$fa_combinations" | grep -qwF "$UNKNOWN_FA_COMBINATION"; then
        note_fail "K/V coverage names $UNKNOWN_FA_COMBINATION, which is not a valid type pair"
    else
        note_pass "K/V coverage names no invalid type pair"
    fi
else
    note_fail "configure did not report '$EXPECTED_FA_MARKER'"
fi

# The compiled object files are the ground truth behind the configure line: they
# show which K/V combinations were actually built rather than which CMake said it
# would build.
compiled_fa_instances="$(docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" -c \
    "find /src/build -name 'fattn-vec-instance-*.cu.o' -printf '%f\n' 2>/dev/null \
     | sed 's/^fattn-vec-instance-//; s/\.cu\.o$//' | sort | tr '\n' ' ' | sed 's/ \$//'" 2>/dev/null)"

if [ "$compiled_fa_instances" = "$EXPECTED_FA_SET" ]; then
    note_pass "compiled K/V instances match the configure line exactly, all $(printf '%s\n' $EXPECTED_FA_COMBINATIONS | wc -l | tr -d '[:space:]') of them"
else
    note_fail "compiled K/V instances are '$compiled_fa_instances', expected the 49 combinations of '$FA_TYPES'"
fi

# The count is asserted on its own as well as through the set comparison, because
# a change here is the thing a future narrowing decision would move, and a bare
# set comparison makes the size of that decision hard to see in the output.
if [ -n "$compiled_fa_instances" ]; then
    compiled_fa_count="$(printf '%s\n' $compiled_fa_instances | wc -l | tr -d '[:space:]')"
    expected_fa_count="$(printf '%s\n' $EXPECTED_FA_COMBINATIONS | wc -l | tr -d '[:space:]')"
    if [ "$compiled_fa_count" -eq "$expected_fa_count" ]; then
        note_pass "the build compiled $compiled_fa_count combinations, the full cross-product rather than a narrowed list"
    else
        note_fail "the build compiled $compiled_fa_count combinations, expected $expected_fa_count"
    fi
fi

# The artefacts the runtime stage reads must exist, and the closure must be
# non-empty, because an empty closure ships an image with no ROCm libraries and
# raises no build-time error.
for artefact in /src/build/bin/llama-server /src/build/bin/libggml-hip.so; do
    if docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" -c "test -f '$artefact'"; then
        note_pass "artefact present: $artefact"
    else
        note_fail "artefact missing: $artefact"
    fi
done

closure_count="$(docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" \
    -c "wc -l < '$CLOSURE_FILE' 2>/dev/null || echo 0" | tr -d '[:space:]')"
if [ "${closure_count:-0}" -gt 0 ] 2>/dev/null; then
    note_pass "library closure recorded $closure_count paths"
else
    note_fail "library closure is empty; the runtime stage would ship no ROCm libraries"
fi

# Every closure path must resolve to a real file. /opt/rocm/lib is a symlink
# through /etc/alternatives into the versioned core tree, so an unresolved entry
# is the specific failure that yields an image with no compute device and no
# build-time error.
broken_paths="$(docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" -c \
    "while read -r closure_path; do [ -f \"\$closure_path\" ] || echo \"unresolved: \$closure_path\"; done < '$CLOSURE_FILE'" 2>&1)"
if [ -z "$broken_paths" ]; then
    note_pass "every closure path resolves to a real file"
else
    note_fail "closure contains unresolved paths: $broken_paths"
fi

# The stage reports the ROCm version it built against, so a base image drifting
# away from the pinned version shows up here rather than at run time.
rocm_version_line="$(docker run --rm --entrypoint /bin/bash "$TEST_IMAGE" \
    -c 'hipconfig --version 2>/dev/null' || true)"
if printf '%s' "$rocm_version_line" | grep -qF "$EXPECTED_ROCM_PREFIX"; then
    note_pass "stage reports ROCm $rocm_version_line"
else
    note_fail "stage reports ROCm '$rocm_version_line', expected a $EXPECTED_ROCM_PREFIX prefix"
fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
