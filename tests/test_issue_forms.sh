#!/usr/bin/env bash
# Tests the GitHub issue forms in .github/ISSUE_TEMPLATE for the structure the
# contribution policy requires: chooser-valid front matter, the mandated
# required fields, free-text axes and runtime fields, the log file uploads,
# and the gate acknowledgement. No YAML parser is available here (no PyYAML,
# no yq), so the suite asserts the exact layout the forms are written in:
# field list items begin "  - id: <id>" at two-space indent, a field-level
# "required: true" (and an upload's "accept:") sits at six-space indent, and a
# checkbox option's "required: true" sits at ten-space indent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
# Directory holding the six issue forms under test.
FORMS="$SRC/.github/ISSUE_TEMPLATE"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# Read one top-level "key: value" scalar from a form file. Front-matter values
# are written as single-line unquoted scalars so this extraction stays exact.
form_key() { sed -n "s/^$2: //p" "$1" | head -1; }

# Print the body block of one form field: from its "  - id: <id>" line up to,
# but excluding, the next field's list item. Depends on the two-space
# list-item indent every form is written with.
field_block() {
    awk -v id="$2" '
        $0 == "  - id: " id { inside = 1; print; next }
        inside && /^  - id: / { inside = 0 }
        inside { print }
    ' "$1"
}

# expect_front_matter <file>: GitHub's chooser needs a name longer than three
# characters and a description; an over-short name hides the form silently.
expect_front_matter() {
    local name description
    name="$(form_key "$1" name)"
    description="$(form_key "$1" description)"
    if [ "${#name}" -gt 3 ]; then note_pass "$(basename "$1") name is longer than three characters"
    else note_fail "$(basename "$1") name '$name' is three characters or fewer"; fi
    if [ -n "$description" ]; then note_pass "$(basename "$1") carries a description"
    else note_fail "$(basename "$1") has no description"; fi
}

# expect_field <file> <id> <type>: the field exists with the expected type.
# The greps below read all input rather than using -q: with pipefail, grep's
# early exit could SIGPIPE the awk writer on a large block and misread a
# passing check as a failure, so every pipeline is consume-all and the
# assertions test the captured output for emptiness.
expect_field() {
    if [ -n "$(field_block "$1" "$2" | grep "^    type: $3$")" ]; then note_pass "$(basename "$1"): $2 is a $3"
    else note_fail "$(basename "$1"): $2 is not a $3"; fi
}

# expect_field_required <file> <id>: the field's validations block demands
# input, so GitHub blocks a submission that leaves it empty.
expect_field_required() {
    if [ -n "$(field_block "$1" "$2" | grep '^      required: true$')" ]; then note_pass "$(basename "$1"): $2 is required"
    else note_fail "$(basename "$1"): $2 is not required"; fi
}

# expect_field_optional <file> <id>: the field carries no required flag, so
# GitHub accepts a submission that leaves it empty (the pasted log excerpts).
expect_field_optional() {
    if [ -n "$(field_block "$1" "$2" | grep '^      required: true$')" ]; then note_fail "$(basename "$1"): $2 is required"
    else note_pass "$(basename "$1"): $2 is optional"; fi
}

# expect_free_text <file> <id>: the field offers no options list, so any value
# is accepted (the free-text axis and runtime decisions).
expect_free_text() {
    if [ -n "$(field_block "$1" "$2" | grep '^[[:space:]]*options:$')" ]; then note_fail "$(basename "$1"): $2 offers a fixed option list"
    else note_pass "$(basename "$1"): $2 accepts free text"; fi
}

# expect_accepts_logs <file> <id>: the upload field's accept list covers the
# log extensions the spec mandates (.log, .txt and .gz).
expect_accepts_logs() {
    local accept_line
    accept_line="$(field_block "$1" "$2" | grep '^      accept: ')"
    if [ -n "$accept_line" ] && [[ "$accept_line" == *".log"* ]] && [[ "$accept_line" == *".txt"* ]] && [[ "$accept_line" == *".gz"* ]]; then
        note_pass "$(basename "$1"): $2 accepts log file extensions"
    else
        note_fail "$(basename "$1"): $2 accept list is missing a log extension"
    fi
}

# expect_fallback_note <file> <id>: the upload field's description carries the
# documented escape hatch for the public-preview upload element — attach the
# file in the issue timeline instead.
expect_fallback_note() {
    if [ -n "$(field_block "$1" "$2" | grep -i 'attach the file in the issue timeline')" ]; then note_pass "$(basename "$1"): $2 describes the timeline fallback"
    else note_fail "$(basename "$1"): $2 does not describe the timeline fallback"; fi
}

# expect_option_required <file> <id>: the checkbox field's option carries
# "required: true" at ten-space indent. GitHub enforces checkbox options
# through the per-option flag, not a field-level validations block.
expect_option_required() {
    if [ -n "$(field_block "$1" "$2" | grep '^          required: true$')" ]; then note_pass "$(basename "$1"): $2 option is required"
    else note_fail "$(basename "$1"): $2 option is not required"; fi
}

# expect_labels <file> <label>: the front matter applies exactly this label.
expect_labels() {
    if grep -qxF "labels: [$2]" "$1"; then note_pass "$(basename "$1") applies label $2"
    else note_fail "$(basename "$1") does not apply label [$2]"; fi
}

# expect_title_prefix <file> <prefix>: the front matter prefills this title.
expect_title_prefix() {
    if grep -qxF "title: \"$2\"" "$1"; then note_pass "$(basename "$1") prefills title \"$2\""
    else note_fail "$(basename "$1") does not prefill title \"$2\""; fi
}

# == Task 1: the general bug form ==

BUG="$FORMS/01-bug-report.yml"

echo "== 01-bug-report.yml exists and is chooser-valid =="
if [ -f "$BUG" ]; then note_pass "01-bug-report.yml exists"
else note_fail "01-bug-report.yml is missing"; fi
expect_front_matter "$BUG"
expect_labels "$BUG" bug
expect_title_prefix "$BUG" "[Bug]: "

echo
echo "== general bug report mandates its report fields =="
# Scenario: General bug form rejects a submission without a log file. GitHub
# blocks the submission until every required field is filled, so requiring
# symptoms, the three runtime detail fields, reproduction steps and the log
# upload is exactly that scenario.
expect_field "$BUG" symptoms textarea
expect_field_required "$BUG" symptoms
for runtime_id in os docker-runtime docker-runtime-version; do
    expect_field "$BUG" "$runtime_id" input
    expect_free_text "$BUG" "$runtime_id"
    expect_field_required "$BUG" "$runtime_id"
done
expect_field "$BUG" reproduction-steps textarea
expect_field_required "$BUG" reproduction-steps
expect_field "$BUG" logs upload
expect_field_required "$BUG" logs
expect_accepts_logs "$BUG" logs
expect_fallback_note "$BUG" logs

echo
echo "== the log excerpt textarea is optional =="
# Scenario: The log excerpt textarea is optional on both bug forms. It carries
# no required flag, so an empty excerpt never blocks the submission.
expect_field "$BUG" logs-excerpt textarea
expect_field_optional "$BUG" logs-excerpt

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
