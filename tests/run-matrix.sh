#!/usr/bin/env bash
# Run the test suite across every ROCm version and GPU architecture found by
# scanning conf/, not from a hardcoded list. A new conf/amd-<version>.env or
# conf/amd-gfx*.env file is picked up automatically on the next run.
#
# The fast argument-resolution check runs once (it is version-independent).
# The docker build-stage and runtime-stage checks run per version/arch pair,
# each taking several minutes. --list prints the discovered pairs and exits
# without invoking docker.
#
# CONF_DIR overrides the scanned directory (the discovery test uses a scratch
# dir through it); it defaults to the repo's conf/.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
CONF_DIR="${CONF_DIR:-$SRC/conf}"
LIST_ONLY='no'

# Read one KEY=value assignment from an env file. Comments and blank lines
# carry no assignments, and assignments in these files never indent the key.
read_key() {
    sed -n "s/^$2=//p" "$1" | head -1
}

# Print one line per version/arch pair: VERSION ARCH BASE CORE PREFIX.
discover_pairs() {
    local version_file arch_file version arch base core prefix target
    shopt -s nullglob
    for version_file in "$CONF_DIR"/amd-[0-9]*.env; do
        version="$(read_key "$version_file" ROCM_VERSION)"
        base="$(read_key "$version_file" ROCM_BASE)"
        core="$(read_key "$version_file" ROCM_CORE_DIR)"
        prefix="${version%.*}"
        for arch_file in "$CONF_DIR"/amd-gfx*.env; do
            target="$(read_key "$arch_file" GPU_TARGET)"
            printf '%s %s %s %s %s\n' "$version" "$target" "$base" "$core" "$prefix"
        done
    done
    shopt -u nullglob
}

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

for arg in "$@"; do
    case "$arg" in
        --list) LIST_ONLY='yes' ;;
        -h|--help)
            printf 'usage: %s [--list]\n' "$(basename "$0")"
            exit 0
            ;;
        *) printf '%s: unrecognised argument %s\n' "$(basename "$0")" "$arg" >&2; exit 2 ;;
    esac
done

PAIRS="$(discover_pairs)"
[ -n "$PAIRS" ] || { printf '%s: no version files in %s\n' "$(basename "$0")" "$CONF_DIR" >&2; exit 2; }

if [ "$LIST_ONLY" = 'yes' ]; then
    printf '%s\n' "$PAIRS"
    exit 0
fi

echo "== argument resolution (version-independent) =="
if bash "$HERE/test_build_args.sh" >/dev/null 2>&1; then
    note_pass "test_build_args.sh"
else
    note_fail "test_build_args.sh"
fi

echo
echo "== stage checks per discovered pair =="
while read -r version target base core prefix; do
    [ -n "$version" ] || continue
    echo "---- $version / $target ----"
    if ROCM_BASE="$base" ROCM_CORE_DIR="$core" GPU_TARGET="$target" \
        EXPECTED_ROCM_PREFIX="$prefix" bash "$HERE/test_build_stage.sh" >/dev/null 2>&1; then
        note_pass "build stage $version / $target"
    else
        note_fail "build stage $version / $target"
        continue
    fi
    if ROCM_BASE="$base" ROCM_CORE_DIR="$core" GPU_TARGET="$target" \
        bash "$HERE/test_runtime_stage.sh" >/dev/null 2>&1; then
        note_pass "runtime stage $version / $target"
    else
        note_fail "runtime stage $version / $target"
    fi
done <<< "$PAIRS"

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
