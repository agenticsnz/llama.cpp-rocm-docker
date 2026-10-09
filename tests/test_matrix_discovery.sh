#!/usr/bin/env bash
# Tests run-matrix.sh's discovery: version and architecture files are found by
# scanning conf/, not from a hardcoded list. Never invokes docker.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
RUNNER="$SRC/tests/run-matrix.sh"
CONF="$SRC/conf"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# expect_output <output-file> <exact line>
expect_output() {
    if grep -qxF -- "$2" "$1"; then note_pass "lists: $2"
    else note_fail "expected line: $2"; fi
}

# reject_output <output-file> <exact line>
reject_output() {
    if grep -qxF -- "$2" "$1"; then note_fail "unexpected line: $2"
    else note_pass "absent: $2"; fi
}

echo "== --list shows every real version file with derived values =="
bash "$RUNNER" --list >"$SCRATCH/l1" 2>"$SCRATCH/le1"
[ $? -eq 0 ] && note_pass "exit 0" || note_fail "exit non-zero"
# Expected lines are composed from the checked-in files, never hardcoded: for
# every discovered version/arch pair the line carries that pair's own values.
shopt -s nullglob
for version_file in "$CONF"/amd-[0-9]*.env; do
    version="$(sed -n 's/^ROCM_VERSION=//p' "$version_file" | head -1)"
    base="$(sed -n 's/^ROCM_BASE=//p' "$version_file" | head -1)"
    core="$(sed -n 's/^ROCM_CORE_DIR=//p' "$version_file" | head -1)"
    for arch_file in "$CONF"/amd-gfx*.env; do
        target="$(sed -n 's/^GPU_TARGET=//p' "$arch_file" | head -1)"
        expect_output "$SCRATCH/l1" "$version $target $base $core ${version%.*}"
    done
done
shopt -u nullglob

echo
echo "== discovery follows the directory, not a hardcoded list =="
mkdir -p "$SCRATCH/conf"
cat > "$SCRATCH/conf/amd-9.9.9.env" <<'ENV'
ROCM_BASE=rocm/dev-ubuntu-24.04:9.9.9-full
ROCM_VERSION=9.9.9
ROCM_BASE_ASSEMBLY=published-multiarch-image
ROCM_CORE_DIR=/opt/rocm/core-9.9
LD_LIBRARY_PATH=/opt/rocm/lib
ENV
cat > "$SCRATCH/conf/amd-gfx9999.env" <<'ENV'
GPU_TARGET=gfx9999
ARCH_STRING=gfx9999
ENV
CONF_DIR="$SCRATCH/conf" bash "$RUNNER" --list >"$SCRATCH/l2" 2>"$SCRATCH/le2"
[ $? -eq 0 ] && note_pass "exit 0" || note_fail "exit non-zero"
expect_output "$SCRATCH/l2" "9.9.9 gfx9999 rocm/dev-ubuntu-24.04:9.9.9-full /opt/rocm/core-9.9 9.9"
reject_output "$SCRATCH/l2" "7.14.1 gfx1200 rocm/dev-ubuntu-24.04:7.14.1-full /opt/rocm/core-7.14 7.14"

echo
echo "== arch files never appear as versions =="
# A version line starts with a version number; an arch token in field one
# would mean an arch file leaked into the version discovery.
if awk '{print $1}' "$SCRATCH/l1" | grep -q '^gfx'; then
    note_fail "arch file listed as a version"
else
    note_pass "no arch file listed as a version"
fi

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
