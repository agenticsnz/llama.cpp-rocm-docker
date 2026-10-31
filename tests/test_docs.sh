#!/usr/bin/env bash
# Tests the documentation split: docs/local-build-guide.md is the single home
# for the build procedure, README no longer carries the moved sections, both
# documents link the guide, and the guide's Tests section lists every suite —
# including the three added by the issue-forms and contribution work, so the
# guide is not stale on arrival.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
README="$SRC/README.md"
CONTRIBUTING="$SRC/CONTRIBUTING.md"
BUILD_GUIDE="$SRC/docs/local-build-guide.md"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

echo "== the build guide exists and carries the moved sections =="
if [ -f "$BUILD_GUIDE" ]; then note_pass "docs/local-build-guide.md exists"
else note_fail "docs/local-build-guide.md is missing"; fi
for heading in "## Prerequisites" "## Building" "### The resulting image" "## Tests"; do
    if grep -qF -- "$heading" "$BUILD_GUIDE"; then note_pass "guide carries: $heading"
    else note_fail "guide is missing: $heading"; fi
done

echo
echo "== README no longer carries the moved build sections =="
# Scenario: README no longer carries the moved build sections; the guide
# contains all four.
for heading in "## Prerequisites" "## Building" "### The resulting image" "## Tests"; do
    if grep -qxF -- "$heading" "$README"; then note_fail "README still carries: $heading"
    else note_pass "README no longer carries: $heading"; fi
done

echo
echo "== both documents link the build guide =="
# Scenario: The local build guide is linked from README and CONTRIBUTING.
for doc in "$README" "$CONTRIBUTING"; do
    if grep -qF "docs/local-build-guide.md" "$doc"; then note_pass "$(basename "$doc") links the build guide"
    else note_fail "$(basename "$doc") does not link the build guide"; fi
done

echo
echo "== README links the contribution guide =="
if grep -qF "CONTRIBUTING.md" "$README"; then note_pass "README links CONTRIBUTING.md"
else note_fail "README does not link CONTRIBUTING.md"; fi

echo
echo "== the guide's Tests section lists every suite =="
for suite in test_build_args.sh test_build_stage.sh test_runtime_stage.sh \
    test_issue_forms.sh test_contributing.sh test_docs.sh; do
    if grep -qF -- "$suite" "$BUILD_GUIDE"; then note_pass "guide lists $suite"
    else note_fail "guide does not list $suite"; fi
done

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]