#!/usr/bin/env bash
# Tests the argument checks of scripts/release_manifest_tool.sh: a missing
# command, an unknown command, an unknown axis name, and a wrong top-level
# name exit 2 with usage on stderr and leave build-conf/project-release.yaml
# byte-identical. Every test runs against a copy of the tree under .tmp/, so
# the committed manifest and conf/ are never touched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
FIXTURE_ROOT="$SRC/.tmp/release-manifest-tests"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

# make_fixture <name>: copy scripts/ and build-conf/ into a fresh fixture, add
# a conf/ holding the four stems from the manifest (each file empty), and print
# the fixture path.
make_fixture() {
    local fixture="$FIXTURE_ROOT/$1"
    rm -rf "$fixture"
    mkdir -p "$fixture/conf"
    cp -r "$SRC/scripts" "$SRC/build-conf" "$fixture/"
    local stem
    for stem in llamacpp-v0.5.0 amd-7.14.1 amd-10.1.0 amd-gfx1200; do
        : > "$fixture/conf/$stem.env"
    done
    printf '%s\n' "$fixture"
}

# expect_usage_error <label> <fixture> [args...]: the tool exits 2, prints the
# usage text on stderr, and leaves the manifest byte-identical.
expect_usage_error() {
    local label="$1" fixture="$2"
    shift 2
    local manifest="$fixture/build-conf/project-release.yaml"
    local saved="$fixture/project-release.saved"
    cp "$manifest" "$saved"
    local stderr_text status
    stderr_text="$("$fixture/scripts/release_manifest_tool.sh" "$@" 2>&1 >/dev/null)"
    status=$?
    if [ "$status" -ne 2 ]; then
        note_fail "$label: exit $status, expected 2"
    elif ! grep -qF "Usage:" <<<"$stderr_text"; then
        note_fail "$label: stderr has no usage text"
    elif ! cmp -s "$manifest" "$saved"; then
        note_fail "$label: manifest changed"
    else
        note_pass "$label"
    fi
}

echo "== no command is a usage error =="
# Scenario: Running with no command is a usage error
expect_usage_error "no arguments exits 2 with usage" "$(make_fixture no-args)"

echo
echo "== release_version commands reject an axis name =="
# Scenario: Getting an axis name as release_version is a usage error
expect_usage_error "--get amd-rocm exits 2 with usage" \
    "$(make_fixture get-axis)" --get amd-rocm

echo
echo "== axis commands reject an unknown axis name =="
# Scenario: Adding to an unknown axis is a usage error
expect_usage_error "--add gpu gfx1200 exits 2 and leaves the manifest unchanged" \
    "$(make_fixture add-unknown-axis)" --add gpu gfx1200

# Scenario: Listing an unknown top-level name is a usage error
expect_usage_error "--list gpu exits 2 with usage" \
    "$(make_fixture list-unknown-axis)" --list gpu

echo
echo "== set and list reject the wrong top-level name =="
expect_usage_error "--set amd-rocm 1.0.0 exits 2 with usage" \
    "$(make_fixture set-wrong-name)" --set amd-rocm 1.0.0

expect_usage_error "--list release_version exits 2 with usage" \
    "$(make_fixture list-release-version)" --list release_version

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
