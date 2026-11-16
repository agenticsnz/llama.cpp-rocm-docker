#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="$HERE/../Dockerfile.rocm"
PASS=0; FAIL=0
note_pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# ARG declarations
for arg in PYTHON_VERSION AMD_SMI_PACKAGE ROCM_SMI_PACKAGE; do
    if grep -q "ARG $arg" "$DOCKERFILE"; then note_pass "Dockerfile declares ARG $arg"
    else note_fail "Dockerfile missing ARG $arg"; fi
done

# python3 in runtime stage
if grep -q "python3" "$DOCKERFILE"; then note_pass "runtime stage installs python3"
else note_fail "runtime stage does not install python3"; fi

# SMI symlinks
if grep -q "ln -sf.*amd-smi" "$DOCKERFILE"; then note_pass "runtime stage symlinks amd-smi"
else note_fail "runtime stage does not symlink amd-smi"; fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]