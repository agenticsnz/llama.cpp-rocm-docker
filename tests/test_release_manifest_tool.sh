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

# Scenario: An axis argument holding two axis names is a usage error
expect_usage_error "--list 'amd-rocm amd-arch' exits 2 with usage" \
    "$(make_fixture list-two-axes)" --list "amd-rocm amd-arch"

expect_usage_error "--add 'llama-cpp amd-rocm' x exits 2 and leaves the manifest unchanged" \
    "$(make_fixture add-two-axes)" --add "llama-cpp amd-rocm" x

expect_usage_error "--delete 'amd-rocm amd-arch' x exits 2 with usage" \
    "$(make_fixture delete-two-axes)" --delete "amd-rocm amd-arch" x

echo
echo "== set and list reject the wrong top-level name =="
expect_usage_error "--set amd-rocm 1.0.0 exits 2 with usage" \
    "$(make_fixture set-wrong-name)" --set amd-rocm 1.0.0

expect_usage_error "--list release_version exits 2 with usage" \
    "$(make_fixture list-release-version)" --list release_version

# with_release_version_line <fixture> <yaml-line>: replaces the release_version
# line of the fixture manifest with <yaml-line>.
with_release_version_line() {
    sed -i "s/^release_version: .*/$2/" "$1/build-conf/project-release.yaml"
}

echo
echo "== release_version read and write =="
# Scenario: Getting release_version works from another working directory
fixture="$(make_fixture get-other-directory)"
out="$(cd /tmp && "$fixture/scripts/release_manifest_tool.sh" --get release_version 2>/dev/null)"
status=$?
if [ "$status" -eq 0 ] && [ "$out" = "1.2.0" ]; then
    note_pass "--get from /tmp prints 1.2.0 and exits 0"
else
    note_fail "--get from /tmp: exit $status, stdout '$out', expected exit 0 and '1.2.0'"
fi

# Scenario: Setting release_version replaces the stored version
fixture="$(make_fixture set-replaces)"
"$fixture/scripts/release_manifest_tool.sh" --set release_version 1.3.0 2>/dev/null
status=$?
if [ "$status" -ne 0 ]; then
    note_fail "--set 1.3.0: exit $status, expected 0"
elif ! grep -qxF 'release_version: "1.3.0"' "$fixture/build-conf/project-release.yaml"; then
    note_fail "--set 1.3.0: file does not contain release_version: \"1.3.0\""
else
    note_pass "--set 1.3.0 replaces the version and keeps it quoted"
fi

# Scenario: Setting release_version rejects a value that is not MAJOR.MINOR.PATCH
fixture="$(make_fixture set-rejects-short)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --set release_version 1.3 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--set 1.3: exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--set 1.3: manifest changed"
else
    note_pass "--set 1.3 exits 1 and leaves the manifest unchanged"
fi

# Review focus: a value with quotes or yq syntax is rejected by the format check
fixture="$(make_fixture set-rejects-injection)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --set release_version '1.3.0"; x' 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--set '1.3.0\"; x': exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--set '1.3.0\"; x': manifest changed"
else
    note_pass "--set '1.3.0\"; x' exits 1 and leaves the manifest unchanged"
fi

# Review focus: an unquoted numeric release_version reads as written
fixture="$(make_fixture get-unquoted-numeric)"
with_release_version_line "$fixture" "release_version: 1.2"
out="$("$fixture/scripts/release_manifest_tool.sh" --get release_version 2>/dev/null)"
status=$?
if [ "$status" -eq 0 ] && [ "$out" = "1.2" ]; then
    note_pass "--get on unquoted release_version: 1.2 prints 1.2"
else
    note_fail "--get on unquoted 1.2: exit $status, stdout '$out', expected exit 0 and '1.2'"
fi

# Review focus: after --set, an unquoted numeric release_version is stored as a string
fixture="$(make_fixture set-unquoted-numeric)"
with_release_version_line "$fixture" "release_version: 1.2"
"$fixture/scripts/release_manifest_tool.sh" --set release_version 1.3.0 2>/dev/null
status=$?
manifest="$fixture/build-conf/project-release.yaml"
tag="$(yq -r '.release_version | tag' "$manifest")"
if [ "$status" -ne 0 ]; then
    note_fail "--set 1.3.0 over unquoted 1.2: exit $status, expected 0"
elif ! grep -qxF 'release_version: "1.3.0"' "$manifest"; then
    note_fail "--set 1.3.0 over unquoted 1.2: file does not contain release_version: \"1.3.0\""
elif [ "$tag" != "!!str" ]; then
    note_fail "--set 1.3.0 over unquoted 1.2: tag is $tag, expected !!str"
else
    note_pass "--set 1.3.0 over unquoted 1.2 writes a quoted !!str"
fi

echo
echo "== release_version with a missing manifest fails =="
# Scenario: Getting release_version with a missing manifest fails
fixture="$(make_fixture get-missing-manifest)"
rm -f "$fixture/build-conf/project-release.yaml"
err="$("$fixture/scripts/release_manifest_tool.sh" --get release_version 2>&1 >/dev/null)"
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--get with missing manifest: exit $status, expected 1"
elif ! grep -qF "build-conf/project-release.yaml" <<<"$err"; then
    note_fail "--get with missing manifest: stderr does not name the manifest"
elif [ -e "$fixture/build-conf/project-release.yaml" ]; then
    note_fail "--get with missing manifest: manifest was created"
else
    note_pass "--get with missing manifest exits 1, names the file, creates nothing"
fi

# Scenario: Setting release_version with a missing manifest fails
fixture="$(make_fixture set-missing-manifest)"
rm -f "$fixture/build-conf/project-release.yaml"
"$fixture/scripts/release_manifest_tool.sh" --set release_version 1.3.0 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--set with missing manifest: exit $status, expected 1"
elif [ -e "$fixture/build-conf/project-release.yaml" ]; then
    note_fail "--set with missing manifest: manifest was created"
else
    note_pass "--set with missing manifest exits 1 and creates nothing"
fi

echo
echo "== list prints axis values =="
# Scenario: Listing amd-rocm prints its values in file order
fixture="$(make_fixture list-amd-rocm)"
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
    note_fail "--list amd-rocm: exit $status, expected 0"
elif [ "$out" != "$(printf 'amd-7.14.1\namd-10.1.0')" ]; then
    note_fail "--list amd-rocm: stdout '$out', expected amd-7.14.1 then amd-10.1.0"
else
    note_pass "--list amd-rocm prints its values in file order and exits 0"
fi

# Scenario: Listing an axis with no values prints nothing
fixture="$(make_fixture list-empty-axis)"
yq -i '.support.amd-arch = []' "$fixture/build-conf/project-release.yaml"
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-arch 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
    note_fail "--list amd-arch with empty axis: exit $status, expected 0"
elif [ -n "$out" ]; then
    note_fail "--list amd-arch with empty axis: stdout '$out', expected empty"
else
    note_pass "--list amd-arch with an empty axis prints nothing and exits 0"
fi

# Scenario: Listing an axis with a missing manifest fails
fixture="$(make_fixture list-missing-manifest)"
rm -f "$fixture/build-conf/project-release.yaml"
err="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>&1 >/dev/null)"
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--list with missing manifest: exit $status, expected 1"
elif ! grep -qF "build-conf/project-release.yaml" <<<"$err"; then
    note_fail "--list with missing manifest: stderr does not name the manifest"
elif [ -e "$fixture/build-conf/project-release.yaml" ]; then
    note_fail "--list with missing manifest: manifest was created"
else
    note_pass "--list with missing manifest exits 1, names the file, creates nothing"
fi

echo
echo "== add appends a value to an axis =="
# Scenario: Adding a new value appends it to the axis list
fixture="$(make_fixture add-new-value)"
: > "$fixture/conf/amd-8.0.0.env"
"$fixture/scripts/release_manifest_tool.sh" --add amd-rocm amd-8.0.0 2>/dev/null
status=$?
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null)"
if [ "$status" -ne 0 ]; then
    note_fail "--add amd-rocm amd-8.0.0: exit $status, expected 0"
elif [ "$out" != "$(printf 'amd-7.14.1\namd-10.1.0\namd-8.0.0')" ]; then
    note_fail "--add amd-rocm amd-8.0.0: list '$out', expected amd-7.14.1, amd-10.1.0, amd-8.0.0"
else
    note_pass "--add amd-rocm amd-8.0.0 appends the value and exits 0"
fi

# Scenario: Adding a value already in the axis list is rejected
fixture="$(make_fixture add-duplicate)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --add amd-rocm amd-10.1.0 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--add duplicate amd-10.1.0: exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--add duplicate amd-10.1.0: manifest changed"
else
    note_pass "--add duplicate amd-10.1.0 exits 1 and leaves the manifest unchanged"
fi

# Scenario: Adding a value with no matching env file is rejected
fixture="$(make_fixture add-no-env-file)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --add amd-arch amd-gfx9999 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--add amd-arch amd-gfx9999: exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--add amd-arch amd-gfx9999: manifest changed"
else
    note_pass "--add amd-arch amd-gfx9999 exits 1 and leaves the manifest unchanged"
fi

# Scenario: Adding a value with a missing manifest fails
fixture="$(make_fixture add-missing-manifest)"
: > "$fixture/conf/amd-8.0.0.env"
rm -f "$fixture/build-conf/project-release.yaml"
"$fixture/scripts/release_manifest_tool.sh" --add amd-rocm amd-8.0.0 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--add with missing manifest: exit $status, expected 1"
elif [ -e "$fixture/build-conf/project-release.yaml" ]; then
    note_fail "--add with missing manifest: manifest was created"
else
    note_pass "--add with missing manifest exits 1 and creates nothing"
fi

# Review focus: a value with a double quote is stored and listed exactly
fixture="$(make_fixture add-quote-character)"
: > "$fixture/conf/amd\"x.env"
"$fixture/scripts/release_manifest_tool.sh" --add amd-rocm 'amd"x' 2>/dev/null
status=$?
last="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null | tail -n 1)"
if [ "$status" -ne 0 ]; then
    note_fail "--add amd-rocm 'amd\"x': exit $status, expected 0"
elif [ "$last" != 'amd"x' ]; then
    note_fail "--add amd-rocm 'amd\"x': last listed value '$last', expected amd\"x"
else
    note_pass "--add amd-rocm 'amd\"x' exits 0 and lists the value exactly"
fi

# CONF_DIR from the environment is the directory the env file check reads
fixture="$(make_fixture add-conf-dir-override)"
override="$FIXTURE_ROOT/add-conf-dir-override-conf"
mkdir -p "$override"
: > "$override/amd-8.0.0.env"
CONF_DIR="$override" "$fixture/scripts/release_manifest_tool.sh" --add amd-rocm amd-8.0.0 2>/dev/null
status=$?
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null)"
if [ "$status" -ne 0 ]; then
    note_fail "CONF_DIR override: exit $status, expected 0"
elif ! grep -qxF 'amd-8.0.0' <<<"$out"; then
    note_fail "CONF_DIR override: amd-8.0.0 not added"
else
    note_pass "CONF_DIR override: env file in that directory is accepted"
fi

echo
echo "== delete removes one axis value =="
# Scenario: Deleting a value removes that value from the axis list
fixture="$(make_fixture delete-removes-value)"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-10.1.0 2>/dev/null
status=$?
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null)"
if [ "$status" -ne 0 ]; then
    note_fail "--delete amd-rocm amd-10.1.0: exit $status, expected 0"
elif [ "$out" != "amd-7.14.1" ]; then
    note_fail "--delete amd-rocm amd-10.1.0: list '$out', expected amd-7.14.1"
else
    note_pass "--delete amd-rocm amd-10.1.0 removes that value and exits 0"
fi

# Scenario: Deleting a value leaves the other axis lists unchanged
fixture="$(make_fixture delete-leaves-other-axes)"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-10.1.0 2>/dev/null
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-arch 2>/dev/null)"
if [ "$out" != "amd-gfx1200" ]; then
    note_fail "--delete amd-rocm amd-10.1.0: amd-arch list '$out', expected amd-gfx1200"
else
    note_pass "--delete amd-rocm amd-10.1.0 leaves amd-arch unchanged"
fi

# Scenario: Deleting a value not in the axis list is rejected
fixture="$(make_fixture delete-not-in-list)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-9.9.9 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--delete amd-rocm amd-9.9.9: exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--delete amd-rocm amd-9.9.9: manifest changed"
else
    note_pass "--delete amd-rocm amd-9.9.9 exits 1 and leaves the manifest unchanged"
fi

# Scenario: Deleting the last value leaves an empty axis
fixture="$(make_fixture delete-last-value)"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-arch amd-gfx1200 2>/dev/null
status=$?
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-arch 2>/dev/null)"
list_status=$?
if [ "$status" -ne 0 ]; then
    note_fail "--delete amd-arch amd-gfx1200: exit $status, expected 0"
elif [ "$(yq -r '.support.amd-arch | length' "$fixture/build-conf/project-release.yaml")" != "0" ]; then
    note_fail "--delete amd-arch amd-gfx1200: amd-arch is not empty"
elif [ "$list_status" -ne 0 ] || [ -n "$out" ]; then
    note_fail "--list amd-arch after deleting last value: exit $list_status, stdout '$out', expected exit 0 and empty"
else
    note_pass "--delete of the last value leaves an empty axis that lists nothing"
fi

# Scenario: Deleting a prefix of a listed value is rejected
fixture="$(make_fixture delete-prefix-rejected)"
manifest="$fixture/build-conf/project-release.yaml"
cp "$manifest" "$fixture/project-release.saved"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-7.14 2>/dev/null
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--delete amd-rocm amd-7.14: exit $status, expected 1"
elif ! cmp -s "$manifest" "$fixture/project-release.saved"; then
    note_fail "--delete amd-rocm amd-7.14: manifest changed"
else
    note_pass "--delete amd-rocm amd-7.14 exits 1 and leaves the manifest unchanged"
fi

# Scenario: Deleting a value keeps a longer value that starts with it
fixture="$(make_fixture delete-prefix-sibling-kept)"
yq -i '.support.amd-rocm += ["amd-7.14.10"]' "$fixture/build-conf/project-release.yaml"
"$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-7.14.1 2>/dev/null
status=$?
out="$("$fixture/scripts/release_manifest_tool.sh" --list amd-rocm 2>/dev/null)"
if [ "$status" -ne 0 ]; then
    note_fail "--delete amd-rocm amd-7.14.1 with amd-7.14.10 present: exit $status, expected 0"
elif [ "$out" != "$(printf 'amd-10.1.0\namd-7.14.10')" ]; then
    note_fail "--delete amd-rocm amd-7.14.1: list '$out', expected amd-10.1.0 and amd-7.14.10"
else
    note_pass "--delete amd-rocm amd-7.14.1 keeps amd-7.14.10"
fi

# Scenario: Deleting with a missing manifest fails
fixture="$(make_fixture delete-missing-manifest)"
rm -f "$fixture/build-conf/project-release.yaml"
err="$("$fixture/scripts/release_manifest_tool.sh" --delete amd-rocm amd-7.14.1 2>&1 >/dev/null)"
status=$?
if [ "$status" -ne 1 ]; then
    note_fail "--delete with missing manifest: exit $status, expected 1"
elif ! grep -qF "build-conf/project-release.yaml" <<<"$err"; then
    note_fail "--delete with missing manifest: stderr does not name the manifest"
elif [ -e "$fixture/build-conf/project-release.yaml" ]; then
    note_fail "--delete with missing manifest: manifest was created"
else
    note_pass "--delete with missing manifest exits 1, names the file, creates nothing"
fi

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
