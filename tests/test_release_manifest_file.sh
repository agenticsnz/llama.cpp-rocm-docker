#!/usr/bin/env bash
# Tests the project release manifest at build-conf/project-release.yaml and the
# yq v4 behaviour the release manifest tool depends on (spec R1 to R4 and R6).
# Each check runs against a fresh fixture under .tmp/, so the committed
# manifest is never changed by this script.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
MANIFEST="$SRC/build-conf/project-release.yaml"
FIXTURE_ROOT="$SRC/.tmp/release-manifest-file-tests"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# new_fixture <name>: prints the path of a fresh, empty fixture directory.
new_fixture() {
    local fixture_dir="$FIXTURE_ROOT/$1"
    rm -rf "$fixture_dir"
    mkdir -p "$fixture_dir"
    printf '%s\n' "$fixture_dir"
}

# copy_manifest <file>: copies the committed manifest into a fixture.
copy_manifest() {
    cp "$MANIFEST" "$1"
}

# expect_equal <label> <expected> <actual>
expect_equal() {
    if [ "$2" = "$3" ]; then note_pass "$1"
    else note_fail "$1 (expected [$2], got [$3])"; fi
}

# R1
check_manifest_file_exists() {
    if [ -f "$MANIFEST" ]; then note_pass "manifest file exists at build-conf/project-release.yaml"
    else note_fail "manifest file is missing at build-conf/project-release.yaml"; fi
}

# R2
check_read_release_version_returns_stored_version() {
    local fixture_dir file out
    fixture_dir="$(new_fixture read-version)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    out="$(yq -r '.release_version' "$file")"
    expect_equal "reading release_version returns 1.2.0" "1.2.0" "$out"
}

check_read_release_version_reports_string_tag() {
    local fixture_dir file out
    fixture_dir="$(new_fixture read-version-tag)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    out="$(yq -r '.release_version | tag' "$file")"
    expect_equal "release_version reports !!str" "!!str" "$out"
}

# R3
check_write_release_version_replaces_value() {
    local fixture_dir file out
    fixture_dir="$(new_fixture write-replaces)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    yq -i '.release_version = "1.3.0"' "$file"
    out="$(yq -r '.release_version' "$file")"
    expect_equal "writing 1.3.0 replaces the stored version" "1.3.0" "$out"
}

check_write_release_version_keeps_double_quotes() {
    local fixture_dir file
    fixture_dir="$(new_fixture write-quotes)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    yq -i '.release_version = "1.3.0"' "$file"
    if grep -qxF 'release_version: "1.3.0"' "$file"; then note_pass "writing keeps release_version double-quoted"
    else note_fail "writing did not keep release_version double-quoted"; fi
}

check_write_numeric_looking_value_reports_string() {
    local fixture_dir file out
    fixture_dir="$(new_fixture write-numeric-looking)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    yq -i '.release_version = "1.3"' "$file"
    out="$(yq -r '.release_version | tag' "$file")"
    expect_equal "writing numeric-looking 1.3 reports !!str" "!!str" "$out"
}

# R4
check_support_keys_list_three_axes() {
    local fixture_dir file out
    fixture_dir="$(new_fixture support-keys)"
    file="$fixture_dir/project-release.yaml"
    copy_manifest "$file"
    out="$(yq -o=json -I=0 '.support | keys' "$file")"
    expect_equal "support keys are llama-cpp, amd-rocm, amd-arch in order" \
        '["llama-cpp","amd-rocm","amd-arch"]' "$out"
}

# R6
check_read_from_missing_file_fails() {
    local fixture_dir file err status
    fixture_dir="$(new_fixture read-missing)"
    file="$fixture_dir/project-release.yaml"
    err="$(yq -r '.release_version' "$file" 2>&1 >/dev/null)"
    status=$?
    expect_equal "reading a missing file exits 1" "1" "$status"
    if printf '%s' "$err" | grep -qi "no such file or directory"; then note_pass "reading a missing file reports no such file or directory"
    else note_fail "reading a missing file did not report no such file or directory"; fi
}

check_write_to_missing_file_fails_without_creating_it() {
    local fixture_dir file status
    fixture_dir="$(new_fixture write-missing)"
    file="$fixture_dir/project-release.yaml"
    yq -i '.release_version = "1.3.0"' "$file" 2>/dev/null
    status=$?
    expect_equal "writing a missing file exits 1" "1" "$status"
    if [ ! -e "$file" ]; then note_pass "writing a missing file does not create it"
    else note_fail "writing a missing file created it"; fi
}

check_read_missing_key_returns_null() {
    local fixture_dir file out status
    fixture_dir="$(new_fixture read-missing-key)"
    file="$fixture_dir/project-release.yaml"
    printf 'other: 1\n' > "$file"
    out="$(yq -r '.release_version' "$file")"
    status=$?
    expect_equal "reading a missing release_version key prints null" "null" "$out"
    expect_equal "reading a missing release_version key exits 0" "0" "$status"
}

check_unquoted_numeric_release_version_reads_as_float() {
    local fixture_dir file out
    fixture_dir="$(new_fixture unquoted-float)"
    file="$fixture_dir/project-release.yaml"
    printf 'release_version: 1.2\n' > "$file"
    out="$(yq -r '.release_version | tag' "$file")"
    expect_equal "unquoted release_version: 1.2 reports !!float" "!!float" "$out"
}

echo "== manifest file exists =="
check_manifest_file_exists

echo
echo "== reading release_version (R2) =="
check_read_release_version_returns_stored_version
check_read_release_version_reports_string_tag

echo
echo "== writing release_version (R3) =="
check_write_release_version_replaces_value
check_write_release_version_keeps_double_quotes
check_write_numeric_looking_value_reports_string

echo
echo "== support axis keys (R4) =="
check_support_keys_list_three_axes

echo
echo "== yq failure behaviour (R6) =="
check_read_from_missing_file_fails
check_write_to_missing_file_fails_without_creating_it
check_read_missing_key_returns_null
check_unquoted_numeric_release_version_reads_as_float

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
