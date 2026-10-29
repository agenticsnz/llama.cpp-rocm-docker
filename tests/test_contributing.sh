#!/usr/bin/env bash
# Tests that CONTRIBUTING.md carries every policy the contribution guide
# promises: the issue forms, the valid label set, the branch naming standard,
# the issue-before-PR gate and new-axes process, the two versioning
# conditions, and the link to the local build guide. The greps pin exact
# phrases; rewording the prose means updating the matching assertion.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
GUIDE="$SRC/CONTRIBUTING.md"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# expect_heading <text>: the guide carries this exact level-2 heading.
expect_heading() {
    if grep -qxF -- "## $1" "$GUIDE"; then note_pass "heading: $1"
    else note_fail "missing heading: $1"; fi
}

# expect_text <phrase>: the guide states this exact phrase.
expect_text() {
    if grep -qF -- "$1" "$GUIDE"; then note_pass "states: $1"
    else note_fail "missing: $1"; fi
}

echo "== CONTRIBUTING.md exists =="
if [ -f "$GUIDE" ]; then note_pass "CONTRIBUTING.md exists"
else note_fail "CONTRIBUTING.md is missing"; fi

echo
echo "== every policy section is present =="
for heading in "Issue forms" "Labels" "Branch naming" \
    "Submitting new axes and combinations" "Versioning" \
    "Building locally" "Running the tests" "Pull requests"; do
    expect_heading "$heading"
done

echo
echo "== the build guide is linked, never restated =="
# Scenario: The local build guide is linked from README and CONTRIBUTING
# (CONTRIBUTING half; the README half and the file's existence are Task 6).
expect_text "docs/local-build-guide.md"

echo
echo "== the valid label set =="
# Scenario: CONTRIBUTING lists all four valid labels.
expect_text "bug, enhancement, infrastructure and add-targets"

echo
echo "== the branch naming standard =="
# Scenario: CONTRIBUTING documents the branch naming format.
expect_text "[label]/issue-[#]-[short-description-kebab-case]"

echo
echo "== the issue-before-PR gate and the new-axes process =="
# Scenario: CONTRIBUTING states the issue-before-PR gate, and outlines how to
# submit new axes — the three config files and the issue that precedes the PR.
expect_text "must name an add-support request issue that already exists"
expect_text "--arch-env"
expect_text "--rocm-env"
expect_text "--config-env"

echo
echo "== the versioning conditions =="
# Scenario: CONTRIBUTING documents the versioning conditions — the image name
# follows the axis versions, and VERSION iterates on Dockerfile.rocm changes.
expect_text "The image name follows the axis versions"
expect_text "iterates when Dockerfile.rocm changes"
expect_text "increments its last component"

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
