# Issue Forms, CONTRIBUTING, and Local Build Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize issue intake and write down the contribution workflow: six GitHub YAML issue forms in `.github/ISSUE_TEMPLATE/`, a full `CONTRIBUTING.md` at the repository root, and `docs/local-build-guide.md` extracted from the README — implementing the design in the spec and resolving issue #3.

**Architecture:** Each issue form is a YAML file whose numeric filename prefix fixes its position in GitHub's template chooser. Front matter (`name`, `description`, `title`, `labels`) makes the form chooser-valid and pre-applies the triage label and title prefix; the `body` is a list of typed fields whose `validations: required: true` flags encode the mandated report contents, with each add-support form's issue-before-PR gate enforced as a required checkbox option. Log evidence is collected as a file attachment via the schema's `upload` element plus an optional pasted-excerpt textarea. Three pure-bash test suites assert the forms and the documentation split by parsing their exact textual layout (this environment has Python 3.12 but no PyYAML and no `yq`). `CONTRIBUTING.md` states the policies — issue forms, labels, branch naming, the new-axes process, versioning — and links the build guide; `docs/local-build-guide.md` receives the README's Prerequisites, Building, The resulting image, and Tests sections verbatim, so build instructions have exactly one home.

**Tech Stack:** GitHub issue forms (YAML), Markdown, Bash (`grep`/`awk`/`sed` test harness), Git.

**Spec:** `docs/superpowers/specs/2026-10-28-issue-forms-contributing-design.md`

## Global Constraints

- **Branch:** `infrastructure/issue-3-contribution-policies-and-safeguards`, already checked out; the spec commits are already on it. Create a worktree only if the executor's workflow requires one.
- **Tests are pure bash**, run from the repository root as `bash tests/<file>.sh`. No PyYAML, no `yq`. Suites follow `tests/test_build_args.sh`'s harness style: `PASS`/`FAIL` counters, `note_pass`/`note_fail`, a final `printf` summary, and `[ "$FAIL" -eq 0 ]` as the last line so the suite's exit status reports the result.
- **The tests parse the forms' exact textual layout.** Every form must be written with: top-level `name:` and `description:` as single-line unquoted scalars containing no colon; `labels: [<label>]` as an unquoted inline flow sequence; `title: "<prefix>"` double-quoted (the value contains a colon); each body field's list item starting at exactly two-space indent (`  - id: <id>`); the field's `type:` at four-space indent; a field-level `validations:` block whose `required: true` sits at six-space indent (and, on `upload` fields, whose `accept:` list also sits at six-space indent); `options:` at six-space indent with option items at eight-space indent and the option's `required: true` at ten-space indent.
- **Filenames (chooser order):** `.github/ISSUE_TEMPLATE/01-bug-report.yml`, `02-bug-report-platform.yml`, `03-feature-request.yml`, `04-add-hardware-support.yml`, `05-add-rocm-version.yml`, `06-add-llama-cpp-version.yml`. No other `.yml` files in that directory; no `config.yml` (blank issues stay available).
- **Form `name:` values (each must exceed three characters or GitHub hides the form):** `Bug report`, `Platform bug report`, `Feature request`, `Add hardware support`, `Add ROCm version`, `Add llama.cpp version`.
- **Labels and title prefixes:** both bug forms apply `labels: [bug]` and `title: "[Bug]: "`; the feature form `labels: [enhancement]` and `title: "[Feature]: "`; the three add-support forms `labels: [add-targets]` with `title: "[Add Hardware]: "`, `title: "[Add ROCm]: "` and `title: "[Add llama.cpp]: "` respectively. No form applies `infrastructure`.
- **Field ids (exact):** axes `rocm-version`, `gpu`, `arch`, `llama-cpp-version` (type `input`, free text, required, on both platform-scoped forms; the add-support forms carry only their relevant axes — `gpu` and `arch` on add-hardware-support, `rocm-version` on add-rocm-version, `llama-cpp-version` on add-llama-cpp-version); report fields `symptoms`, `reproduction-steps` (type `textarea`, required, on both bug forms), runtime details `os`, `docker-runtime`, `docker-runtime-version` (type `input`, free text, required, on both bug forms); log evidence `logs` on both bug forms and `evidence` on each add-support form (type `upload`, required, `accept` listing `.log`, `.txt`, `.gz`, description containing the fallback about attaching in the issue timeline, and `evidence` descriptions also containing the word `verbose`); log excerpts `logs-excerpt` on both bug forms and `evidence-excerpt` on each add-support form (type `textarea`, not required); feature fields `description`, `improvement`, `implementation-suggestion` (type `textarea`, required); `gate-acknowledgement` (type `checkbox`, its option carrying `required: true`, on each add-support form).
- **Free text means no `options:` and no `type: dropdown` on any axis or runtime field.** The tests fail any such field that offers a fixed choice list.
- **Documentation paths:** `CONTRIBUTING.md` at the repository root; build guide at `docs/local-build-guide.md`. README keeps the overview and the config-file/axes reference tables; the guide gains `## Prerequisites`, `## Building`, `### The resulting image`, and `## Tests`. Both README and CONTRIBUTING link `docs/local-build-guide.md`; README also links `CONTRIBUTING.md`.
- **CONTRIBUTING section headings (exact, tested):** `## Issue forms`, `## Labels`, `## Branch naming`, `## Submitting new axes and combinations`, `## Versioning`, `## Building locally`, `## Running the tests`, `## Pull requests`.
- **Prose phrases the tests grep for:** CONTRIBUTING must contain the literal strings `docs/local-build-guide.md`, `bug, enhancement, infrastructure and add-targets`, `[label]/issue-[#]-[short-description-kebab-case]`, `--arch-env`, `--rocm-env`, `--config-env`, `must name an add-support request issue that already exists`, `The image name follows the axis versions`, `iterates when Dockerfile.rocm changes`, `increments its last component`. If the prose is reworded, update the assertions in the same commit.
- **No `gh` CLI in this environment.** Nothing in the plan requires it; the forms only become active once the PR merges to the default branch, so the live chooser check is a post-merge manual step, noted in Task 6.
- **Commit after each task**, staging only that task's files, with a descriptive imperative subject. No attribution or co-author lines. Never push unless asked.

## Review Focus

Conditions the spec implies that a plausible implementation would get wrong silently. The owning task carries the test or the check.

1. **The issue-before-PR gate on each add-support form is enforced by a per-option `required: true` under `attributes.options`, not a field-level `validations:` block.** GitHub enforces checkbox options through the option flag; a field-level `required` on a checkbox is not what blocks submission, so the gate would silently pass unchecked. → Task 4
2. **Axis and runtime fields must carry no `options:` list.** A dropdown would satisfy "field present" in every existence test while violating the free-text decision and going stale the moment a new combination or tool lands. → Tasks 1, 2 and 4
3. **The moved `## Tests` section must list the three new suites, not only the original three.** The guide would be stale on arrival otherwise, and the new tests would be undiscoverable. → Task 6
4. **CONTRIBUTING must link the build guide rather than restate build steps.** Copying the commands into CONTRIBUTING recreates the two-copies drift the guide exists to prevent. → Task 5
5. **Every form `name:` must exceed three characters.** GitHub hides an over-short form from the chooser with no error anywhere — the suite's front-matter check is the only thing that notices. → Tasks 1–4

---

### Task 1: General bug report form and the form-test harness

Creates the first form and the shared bash helpers the next three tasks extend.

**Spec scenarios:** "General bug form rejects a submission without a log file" (via the log-upload-required check, alongside the other mandated fields), "The log excerpt textarea is optional on both bug forms" (the general-form half; the platform half is re-checked in Task 2), and the general-bug half of "Bug forms apply the bug label and title prefix". Front-matter validity for this file is checked here and re-checked across all six in Task 4.

**Files:**
- Create: `.github/ISSUE_TEMPLATE/01-bug-report.yml`
- Create: `tests/test_issue_forms.sh`

**Interfaces:**
- Consumes: GitHub's issue-form schema (`.yml` in `.github/ISSUE_TEMPLATE/` with `name`, `description`, `title`, `labels`, `body`), including the `upload` element with its `required` and `accept` validations.
- Produces: `tests/test_issue_forms.sh` runnable as `bash tests/test_issue_forms.sh` from the repository root; helpers `form_key`, `field_block`, `expect_front_matter`, `expect_field`, `expect_field_required`, `expect_field_optional`, `expect_free_text`, `expect_accepts_logs`, `expect_fallback_note`, `expect_option_required`, `expect_labels`, `expect_title_prefix` that later tasks reuse.

- [ ] **Step 1: Write the failing test**

Create `tests/test_issue_forms.sh`:

````bash
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
````

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_issue_forms.sh`

Expected: the existence, front-matter, label, prefix, type and required checks report `FAIL`; the free-text, excerpt-optional and no-config.yml checks pass on their own — they are negative assertions that hold trivially while the files are absent, so the summary is not all-red; exit status non-zero. If any existence or required check passes, the test is wrong — fix it before continuing.

- [ ] **Step 3: Write the form**

Create `.github/ISSUE_TEMPLATE/01-bug-report.yml`:

```yaml
name: Bug report
description: A bug that is not tied to a particular ROCm, GPU, architecture or llama.cpp combination
title: "[Bug]: "
labels: [bug]
body:
  - id: symptoms
    type: textarea
    attributes:
      label: Symptoms
      description: What happens, what you expected to happen, and how the failure shows itself.
    validations:
      required: true
  - id: os
    type: input
    attributes:
      label: OS
      description: The host operating system and version, e.g. Ubuntu 24.04.
    validations:
      required: true
  - id: docker-runtime
    type: input
    attributes:
      label: Docker runtime
      description: The container runtime used to launch the image, e.g. Docker Engine or Podman — free text, so any runtime is accepted.
    validations:
      required: true
  - id: docker-runtime-version
    type: input
    attributes:
      label: Docker runtime version
      description: The runtime's version string, e.g. 27.3.1.
    validations:
      required: true
  - id: reproduction-steps
    type: textarea
    attributes:
      label: Steps to reproduce
      description: The exact commands and configuration used to reach the failure.
    validations:
      required: true
  - id: logs
    type: upload
    attributes:
      label: Log file
      description: The full output of the failing run, attached as a file. If the upload fails, attach the file in the issue timeline after submitting.
    validations:
      required: true
      accept: .log,.txt,.gz
  - id: logs-excerpt
    type: textarea
    attributes:
      label: Log excerpt
      description: A short paste of the most relevant lines, if it helps — the attached file remains the required evidence.
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test_issue_forms.sh`

Expected: every check reports `ok`, the summary reads `=== N passed, 0 failed ===`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add .github/ISSUE_TEMPLATE/01-bug-report.yml tests/test_issue_forms.sh
git commit -m "Add the general bug report issue form

- First of six issue forms; requires symptoms, the three free-text runtime
  detail inputs (OS, Docker runtime, runtime version), reproduction steps,
  and a required log file upload accepting .log, .txt and .gz, plus an
  optional pasted log excerpt
- Adds the bash form-test harness that the remaining form tasks extend;
  no YAML parser is available, so the suite parses the forms' fixed layout"
```

---

### Task 2: Platform bug report form

Adds the platform-scoped bug form and its axis checks.

**Spec scenarios:** "Platform bug form accepts free-text axis values", "Platform bug form rejects a submission missing an axis" (the "Axes are required" decision), "Platform bug form rejects a submission without symptoms", "A complete bug report is accepted on both bug forms", "The log excerpt textarea is optional on both bug forms" (the platform half), and the platform-bug half of "Bug forms apply the bug label and title prefix".

**Files:**
- Create: `.github/ISSUE_TEMPLATE/02-bug-report-platform.yml`
- Modify: `tests/test_issue_forms.sh` (append the Task 2 section before the summary lines)

**Interfaces:**
- Consumes: the Task 1 helpers in `tests/test_issue_forms.sh`.
- Produces: axis ids `rocm-version`, `gpu`, `arch`, `llama-cpp-version` as required free-text `input` fields, asserted on both bug forms from now on.

- [ ] **Step 1: Write the failing test**

In `tests/test_issue_forms.sh`, insert before the `printf '=== %d passed...` summary block:

```bash
# == Task 2: the platform bug form ==

PLATFORM="$FORMS/02-bug-report-platform.yml"

echo
echo "== 02-bug-report-platform.yml exists and is chooser-valid =="
if [ -f "$PLATFORM" ]; then note_pass "02-bug-report-platform.yml exists"
else note_fail "02-bug-report-platform.yml is missing"; fi
expect_front_matter "$PLATFORM"
expect_labels "$PLATFORM" bug
expect_title_prefix "$PLATFORM" "[Bug]: "

echo
echo "== platform axes are free text and required =="
# Scenario: Platform bug form accepts free-text axis values, and rejects a
# submission missing an axis. Each axis is an input with no options list, so
# any combination is accepted, and required, so GitHub blocks an empty one.
for axis_id in rocm-version gpu arch llama-cpp-version; do
    expect_field "$PLATFORM" "$axis_id" input
    expect_free_text "$PLATFORM" "$axis_id"
    expect_field_required "$PLATFORM" "$axis_id"
done

echo
echo "== platform bug report mandates its report fields =="
# Scenario: Platform bug form rejects a submission without symptoms. GitHub
# blocks the submission until every required field is filled, so requiring
# symptoms, the three runtime detail fields, reproduction steps and the log
# upload is exactly that scenario.
expect_field "$PLATFORM" symptoms textarea
expect_field_required "$PLATFORM" symptoms
for runtime_id in os docker-runtime docker-runtime-version; do
    expect_field "$PLATFORM" "$runtime_id" input
    expect_free_text "$PLATFORM" "$runtime_id"
    expect_field_required "$PLATFORM" "$runtime_id"
done
expect_field "$PLATFORM" reproduction-steps textarea
expect_field_required "$PLATFORM" reproduction-steps
expect_field "$PLATFORM" logs upload
expect_field_required "$PLATFORM" logs
expect_accepts_logs "$PLATFORM" logs
expect_fallback_note "$PLATFORM" logs

echo
echo "== the platform log excerpt textarea is optional =="
# Scenario: The log excerpt textarea is optional on both bug forms (platform
# half; the general half is checked in Task 1).
expect_field "$PLATFORM" logs-excerpt textarea
expect_field_optional "$PLATFORM" logs-excerpt

echo
echo "== a complete bug report is accepted on both bug forms =="
# Scenario: A complete bug report is accepted on both bug forms. GitHub blocks
# submission until every required field is filled, so requiring all the
# mandated fields on both forms is exactly that scenario.
for bug_form in "$BUG" "$PLATFORM"; do
    for report_id in symptoms reproduction-steps logs; do
        expect_field_required "$bug_form" "$report_id"
    done
    for runtime_id in os docker-runtime docker-runtime-version; do
        expect_field_required "$bug_form" "$runtime_id"
    done
done
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_issue_forms.sh`

Expected: the Task 1 checks still pass; the new platform existence, type and required checks report `FAIL` (the free-text and excerpt-optional checks pass trivially on the missing file); exit status non-zero.

- [ ] **Step 3: Write the form**

Create `.github/ISSUE_TEMPLATE/02-bug-report-platform.yml`:

```yaml
name: Platform bug report
description: A bug against a specific ROCm, GPU, architecture and llama.cpp combination
title: "[Bug]: "
labels: [bug]
body:
  - id: rocm-version
    type: input
    attributes:
      label: ROCm version
      description: The ROCm release the image was built against, e.g. 7.14.1.
    validations:
      required: true
  - id: gpu
    type: input
    attributes:
      label: GPU
      description: The GPU card target, e.g. gfx1200.
    validations:
      required: true
  - id: arch
    type: input
    attributes:
      label: Arch
      description: The architecture string from the image tag, e.g. gfx1200 or RDNA4.
    validations:
      required: true
  - id: llama-cpp-version
    type: input
    attributes:
      label: llama.cpp version
      description: The llama.cpp tag the image was built from, e.g. v0.5.0.
    validations:
      required: true
  - id: symptoms
    type: textarea
    attributes:
      label: Symptoms
      description: What happens, what you expected to happen, and how the failure shows itself.
    validations:
      required: true
  - id: os
    type: input
    attributes:
      label: OS
      description: The host operating system and version, e.g. Ubuntu 24.04.
    validations:
      required: true
  - id: docker-runtime
    type: input
    attributes:
      label: Docker runtime
      description: The container runtime used to launch the image, e.g. Docker Engine or Podman — free text, so any runtime is accepted.
    validations:
      required: true
  - id: docker-runtime-version
    type: input
    attributes:
      label: Docker runtime version
      description: The runtime's version string, e.g. 27.3.1.
    validations:
      required: true
  - id: reproduction-steps
    type: textarea
    attributes:
      label: Steps to reproduce
      description: The exact commands and configuration used to reach the failure.
    validations:
      required: true
  - id: logs
    type: upload
    attributes:
      label: Log file
      description: The full output of the failing run, attached as a file. If the upload fails, attach the file in the issue timeline after submitting.
    validations:
      required: true
      accept: .log,.txt,.gz
  - id: logs-excerpt
    type: textarea
    attributes:
      label: Log excerpt
      description: A short paste of the most relevant lines, if it helps — the attached file remains the required evidence.
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test_issue_forms.sh`

Expected: all checks `ok`, `=== N passed, 0 failed ===`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add .github/ISSUE_TEMPLATE/02-bug-report-platform.yml tests/test_issue_forms.sh
git commit -m "Add the platform bug report issue form

- Adds the four free-text axis fields (ROCm, GPU, arch, llama.cpp version),
  required, alongside the mandated report fields and the three free-text
  runtime detail inputs, the log upload, and the optional excerpt
- Extends the form suite with axis, runtime, log-upload and both-forms checks"
```

---

### Task 3: Feature request form

**Spec scenarios:** "Feature request rejects a submission without an implementation suggestion" (via the implementation-suggestion-required check), "A complete feature request is accepted", and "The feature form applies the enhancement label and title prefix".

**Files:**
- Create: `.github/ISSUE_TEMPLATE/03-feature-request.yml`
- Modify: `tests/test_issue_forms.sh` (append the Task 3 section before the summary lines)

**Interfaces:**
- Consumes: the Task 1 helpers.
- Produces: feature ids `description`, `improvement`, `implementation-suggestion` as required textareas.

- [ ] **Step 1: Write the failing test**

In `tests/test_issue_forms.sh`, insert before the summary block:

```bash
# == Task 3: the feature request form ==

FEATURE="$FORMS/03-feature-request.yml"

echo
echo "== 03-feature-request.yml exists and is chooser-valid =="
if [ -f "$FEATURE" ]; then note_pass "03-feature-request.yml exists"
else note_fail "03-feature-request.yml is missing"; fi
expect_front_matter "$FEATURE"
expect_labels "$FEATURE" enhancement
expect_title_prefix "$FEATURE" "[Feature]: "

echo
echo "== feature request mandates description, improvement and a suggestion =="
# Scenario: Feature request rejects a submission without an implementation
# suggestion; a complete request fills all three fields.
expect_field "$FEATURE" description textarea
expect_field_required "$FEATURE" description
expect_field "$FEATURE" improvement textarea
expect_field_required "$FEATURE" improvement
expect_field "$FEATURE" implementation-suggestion textarea
expect_field_required "$FEATURE" implementation-suggestion
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_issue_forms.sh`

Expected: Tasks 1–2 checks pass; every Task 3 check reports `FAIL`; exit status non-zero.

- [ ] **Step 3: Write the form**

Create `.github/ISSUE_TEMPLATE/03-feature-request.yml`:

```yaml
name: Feature request
description: A new capability or change, not tied to a particular platform combination
title: "[Feature]: "
labels: [enhancement]
body:
  - id: description
    type: textarea
    attributes:
      label: Description
      description: What you want, in detail — the behaviour, the use case, and the problem it solves.
    validations:
      required: true
  - id: improvement
    type: textarea
    attributes:
      label: What it improves
      description: How this change makes the image, the build, or the workflow better than it is today.
    validations:
      required: true
  - id: implementation-suggestion
    type: textarea
    attributes:
      label: Implementation suggestion
      description: At least one way this could be implemented — files to change, flags to add, or prior art to follow.
    validations:
      required: true
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test_issue_forms.sh`

Expected: all checks `ok`, `=== N passed, 0 failed ===`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add .github/ISSUE_TEMPLATE/03-feature-request.yml tests/test_issue_forms.sh
git commit -m "Add the feature request issue form

- Requires a description, what it improves, and at least one implementation
  suggestion
- Applies the enhancement label and the [Feature] title prefix"
```

---

### Task 4: The three add-support forms, chooser order, and blank-issue availability

**Spec scenarios:** "Add-hardware-support rejects a submission missing an axis", "Add-rocm-version rejects a submission missing the ROCm version", "Add-llama-cpp-version rejects a submission missing the llama.cpp version", "Add-support forms reject a submission without evidence", "Add-support forms reject a submission without acknowledgement", "A complete add-support request with verbose startup evidence is accepted" (via relevant axes, evidence-with-verbose-description, and acknowledgement all required), the three label/prefix scenarios ("The add-hardware-support form applies the add-targets label and title prefix", and the add-rocm-version and add-llama-cpp-version equivalents), "The chooser lists the forms in numeric order", "Blank issues stay available alongside the forms", and "Every form carries front matter the chooser accepts" (all six files).

**Files:**
- Create: `.github/ISSUE_TEMPLATE/04-add-hardware-support.yml`
- Create: `.github/ISSUE_TEMPLATE/05-add-rocm-version.yml`
- Create: `.github/ISSUE_TEMPLATE/06-add-llama-cpp-version.yml`
- Modify: `tests/test_issue_forms.sh` (append the Task 4 section before the summary lines)

**Interfaces:**
- Consumes: the Task 1 helpers in `tests/test_issue_forms.sh`.
- Produces: add-support form ids per form — the relevant axis only (`gpu` and `arch` on add-hardware-support, `rocm-version` on add-rocm-version, `llama-cpp-version` on add-llama-cpp-version) as required free-text `input` fields; `evidence` (required `upload` with the log `accept` list, its description naming the verbose flag and the timeline fallback); `evidence-excerpt` (optional `textarea`); `gate-acknowledgement` (checkbox with a required option); directory-level checks over all six forms.

- [ ] **Step 1: Write the failing test**

In `tests/test_issue_forms.sh`, insert before the summary block:

```bash
# == Task 4: the three add-support forms and the chooser ==

HARDWARE="$FORMS/04-add-hardware-support.yml"
ROCM="$FORMS/05-add-rocm-version.yml"
LLAMACPP="$FORMS/06-add-llama-cpp-version.yml"

echo
echo "== each add-support form exists and is chooser-valid =="
for add_form in "$HARDWARE" "$ROCM" "$LLAMACPP"; do
    if [ -f "$add_form" ]; then note_pass "$(basename "$add_form") exists"
    else note_fail "$(basename "$add_form") is missing"; fi
    expect_front_matter "$add_form"
    expect_labels "$add_form" add-targets
done
# Each category's prefix is static front matter on its own form file.
expect_title_prefix "$HARDWARE" "[Add Hardware]: "
expect_title_prefix "$ROCM" "[Add ROCm]: "
expect_title_prefix "$LLAMACPP" "[Add llama.cpp]: "

echo
echo "== each add-support form asks its relevant axes, free text and required =="
# Scenario: Add-hardware-support rejects a submission missing an axis;
# add-rocm-version rejects a submission missing the ROCm version;
# add-llama-cpp-version rejects a submission missing the llama.cpp version.
# Each form carries only the axes its category needs; the target being added
# is free text in the axis field itself.
check_axes() {
    local add_form="$1"; shift
    local axis_id
    for axis_id in "$@"; do
        expect_field "$add_form" "$axis_id" input
        expect_free_text "$add_form" "$axis_id"
        expect_field_required "$add_form" "$axis_id"
    done
}
check_axes "$HARDWARE" gpu arch
check_axes "$ROCM" rocm-version
check_axes "$LLAMACPP" llama-cpp-version

echo
echo "== each add-support form requires verbose startup evidence =="
# Scenario: Add-support forms reject a submission without evidence. Evidence
# is llama.cpp logs produced with the verbose flag showing startup on the
# target platform, attached as a file; the description must name the verbose
# flag and the timeline fallback. The excerpt stays optional everywhere.
for add_form in "$HARDWARE" "$ROCM" "$LLAMACPP"; do
    expect_field "$add_form" evidence upload
    expect_field_required "$add_form" evidence
    expect_accepts_logs "$add_form" evidence
    expect_fallback_note "$add_form" evidence
    if [ -n "$(field_block "$add_form" evidence | grep -i 'verbose')" ]; then
        note_pass "$(basename "$add_form"): evidence description names the verbose flag"
    else
        note_fail "$(basename "$add_form"): evidence description does not mention the verbose flag"
    fi
    expect_field "$add_form" evidence-excerpt textarea
    expect_field_optional "$add_form" evidence-excerpt
done

echo
echo "== each add-support form requires the issue-before-PR acknowledgement =="
# Scenario: Add-support forms reject a submission without acknowledgement. The
# gate lives on the checkbox option's required flag, not a field-level block.
for add_form in "$HARDWARE" "$ROCM" "$LLAMACPP"; do
    expect_field "$add_form" gate-acknowledgement checkbox
    expect_option_required "$add_form" gate-acknowledgement
done

echo
echo "== the chooser lists the forms in numeric order =="
# Scenario: The chooser lists the forms in numeric order — general bug,
# platform bug, feature request, add hardware support, add ROCm version, add
# llama.cpp version. Any other yml file here would change the chooser and
# fails this comparison.
expected_order="01-bug-report.yml
02-bug-report-platform.yml
03-feature-request.yml
04-add-hardware-support.yml
05-add-rocm-version.yml
06-add-llama-cpp-version.yml"
actual_order="$(cd "$FORMS" && ls -- *.yml | sort)"
if [ "$actual_order" = "$expected_order" ]; then note_pass "forms sort into chooser order"
else note_fail "unexpected files or order in $FORMS: $actual_order"; fi

echo
echo "== blank issues stay available alongside the forms =="
# Scenario: Blank issues stay available alongside the forms. A config.yml
# would let the repository disable them, so its absence is the assertion.
if [ -e "$FORMS/config.yml" ]; then note_fail "config.yml is present; blank issues are configured away"
else note_pass "no config.yml; blank issues stay available"; fi

echo
echo "== every form carries chooser-valid front matter =="
# Scenario: Every form carries front matter the chooser accepts — re-checked
# across all six files together.
for form in "$FORMS"/0*.yml; do
    expect_front_matter "$form"
done
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_issue_forms.sh`

Expected: Tasks 1–3 checks pass; the new add-support existence, front-matter, label, prefix, type, required, evidence and acknowledgement checks report `FAIL`, and the chooser-order comparison fails since the three add-support files are absent (the free-text, excerpt-optional and no-config.yml checks pass trivially); exit status non-zero.

- [ ] **Step 3: Write the form**

Create `.github/ISSUE_TEMPLATE/04-add-hardware-support.yml`:

```yaml
name: Add hardware support
description: Request support for a new GPU card or architecture target
title: "[Add Hardware]: "
labels: [add-targets]
body:
  - id: gpu
    type: input
    attributes:
      label: GPU
      description: The GPU card target to add, e.g. gfx90a.
    validations:
      required: true
  - id: arch
    type: input
    attributes:
      label: Arch
      description: The architecture string for the image tag, e.g. gfx90a or CDNA2.
    validations:
      required: true
  - id: evidence
    type: upload
    attributes:
      label: Evidence
      description: llama-server startup logs produced with the verbose flag, showing the server starting on the target platform. If the upload fails, attach the file in the issue timeline after submitting.
    validations:
      required: true
      accept: .log,.txt,.gz
  - id: evidence-excerpt
    type: textarea
    attributes:
      label: Evidence excerpt
      description: A short paste of the most relevant startup lines, if it helps — the attached file remains the required evidence.
  - id: gate-acknowledgement
    type: checkbox
    attributes:
      label: Issue-before-PR acknowledgement
      options:
        - label: I understand that an add-support request issue must exist before a pull request merging configuration files for this combination is opened.
          required: true
```

Create `.github/ISSUE_TEMPLATE/05-add-rocm-version.yml` — same evidence, excerpt and acknowledgement fields; only the axis and the front matter differ:

```yaml
name: Add ROCm version
description: Request support for a new ROCm release version
title: "[Add ROCm]: "
labels: [add-targets]
body:
  - id: rocm-version
    type: input
    attributes:
      label: ROCm version
      description: The ROCm release to build against, e.g. 7.14.1.
    validations:
      required: true
  - id: evidence
    type: upload
    attributes:
      label: Evidence
      description: llama-server startup logs produced with the verbose flag, showing the server starting on the target platform. If the upload fails, attach the file in the issue timeline after submitting.
    validations:
      required: true
      accept: .log,.txt,.gz
  - id: evidence-excerpt
    type: textarea
    attributes:
      label: Evidence excerpt
      description: A short paste of the most relevant startup lines, if it helps — the attached file remains the required evidence.
  - id: gate-acknowledgement
    type: checkbox
    attributes:
      label: Issue-before-PR acknowledgement
      options:
        - label: I understand that an add-support request issue must exist before a pull request merging configuration files for this combination is opened.
          required: true
```

Create `.github/ISSUE_TEMPLATE/06-add-llama-cpp-version.yml` — again the same three non-axis fields:

```yaml
name: Add llama.cpp version
description: Request support for a new llama.cpp release tag
title: "[Add llama.cpp]: "
labels: [add-targets]
body:
  - id: llama-cpp-version
    type: input
    attributes:
      label: llama.cpp version
      description: The llama.cpp tag to build from, e.g. v0.5.0.
    validations:
      required: true
  - id: evidence
    type: upload
    attributes:
      label: Evidence
      description: llama-server startup logs produced with the verbose flag, showing the server starting on the target platform. If the upload fails, attach the file in the issue timeline after submitting.
    validations:
      required: true
      accept: .log,.txt,.gz
  - id: evidence-excerpt
    type: textarea
    attributes:
      label: Evidence excerpt
      description: A short paste of the most relevant startup lines, if it helps — the attached file remains the required evidence.
  - id: gate-acknowledgement
    type: checkbox
    attributes:
      label: Issue-before-PR acknowledgement
      options:
        - label: I understand that an add-support request issue must exist before a pull request merging configuration files for this combination is opened.
          required: true
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test_issue_forms.sh`

Expected: all checks `ok`, `=== N passed, 0 failed ===`, exit status 0. If the acknowledgement check fails while the YAML looks right, confirm `required: true` sits under the option at ten-space indent, not under a `validations:` block (Review Focus 1).

- [ ] **Step 5: Commit**

```bash
git add .github/ISSUE_TEMPLATE/04-add-hardware-support.yml \
        .github/ISSUE_TEMPLATE/05-add-rocm-version.yml \
        .github/ISSUE_TEMPLATE/06-add-llama-cpp-version.yml \
        tests/test_issue_forms.sh
git commit -m "Add the three add-support issue forms

- One form per category with its own static title prefix ([Add Hardware],
  [Add ROCm], [Add llama.cpp]) and only its relevant axes, since GitHub
  title prefixes are static front matter per file
- Each requires a verbose llama-server startup log upload and an
  acknowledgement of the issue-before-PR rule as a required checkbox option
- Extends the form suite with the six-form chooser order and the all-six
  front-matter check"
```

---

### Task 5: CONTRIBUTING.md

**Spec scenarios:** "CONTRIBUTING states the issue-before-PR gate", "CONTRIBUTING outlines how to submit new axes", "CONTRIBUTING lists all four valid labels", "CONTRIBUTING documents the versioning conditions", and "CONTRIBUTING documents the branch naming format". The CONTRIBUTING half of "The local build guide is linked from README and CONTRIBUTING" is asserted here; the README half and the guide file's existence land in Task 6.

**Files:**
- Create: `CONTRIBUTING.md`
- Create: `tests/test_contributing.sh`

**Interfaces:**
- Consumes: the six form filenames and labels from Tasks 1–4; the build-guide link target `docs/local-build-guide.md`, created in Task 6.
- Produces: `bash tests/test_contributing.sh`; CONTRIBUTING links the build guide and names every policy the spec requires.

- [ ] **Step 1: Write the failing test**

Create `tests/test_contributing.sh`:

````bash
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

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
````

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_contributing.sh`

Expected: the existence check and every subsequent check report `FAIL`; exit status non-zero.

- [ ] **Step 3: Write CONTRIBUTING.md**

Create `CONTRIBUTING.md` with these sections. The test greps the exact phrases marked in bold below, so keep them verbatim; the rest is prose in the repository's existing documentation voice (single-line paragraphs, no hard wraps).

```markdown
# Contributing

Thank you for contributing. This guide covers issue intake, branch naming, adding new build targets, versioning, and the pull request process.

## Issue forms

Six issue forms are available in the new-issue chooser, each applying its label and a title prefix: a general bug report ([Bug]: , label bug) for problems not tied to a particular combination, a platform bug report ([Bug]: , label bug) for problems against a specific ROCm / GPU / architecture / llama.cpp combination, a feature request ([Feature]: , label enhancement), and three add-support forms for new build targets — add hardware support ([Add Hardware]: , label add-targets), add ROCm version ([Add ROCm]: , label add-targets) and add llama.cpp version ([Add llama.cpp]: , label add-targets). Blank issues remain available for anything that does not fit a form.

## Labels

Issues carry one of four labels: **bug, enhancement, infrastructure and add-targets**. The forms apply their own label; infrastructure is applied by maintainers during triage and is available to blank issues, so no form carries it by default.

## Branch naming

Branch names follow **[label]/issue-[#]-[short-description-kebab-case]**. `[label]` is the issue's applied label, one of bug, enhancement, infrastructure or add-targets. `[#]` is the issue number, and the short description is three to five kebab-case words derived from the issue title, for example `bug/issue-42-container-toolkit-not-detected`. Every branch names an issue, so an issue exists before any branch does.
```

Continue with the remaining sections:

```markdown
## Submitting new axes and combinations

A combination is one ROCm release, one GPU architecture and one llama.cpp tag. To request one, open the matching add-support issue — add hardware support, add ROCm version or add llama.cpp version, depending on what is new: it must attach llama-server startup logs produced with the verbose flag on the target platform, so the combination is known to work before any file is written. A pull request that merges configuration files for a combination **must name an add-support request issue that already exists**.

Each axis of the build is owned by one configuration file, selected on the command line as **--arch-env** (the GPU architecture), **--rocm-env** (the ROCm release) and **--config-env** (the axis-neutral settings). A new combination on an existing axis adds one file; a key found in more than one file resolves to the file that owns its axis, and the losing copy is reported and discarded.

A new axis — a dimension the build does not yet vary by — starts as an infrastructure-labelled issue explaining what varies, which file would own it, and which build arguments it would supply. Discuss it there before writing any configuration, because the axis changes what every image name means.

## Versioning

**The image name follows the axis versions**, exactly as today: `build-rocm.sh` composes `REGISTRY/agenticsnz/llama.cpp-<LLAMA_CPP_VERSION>-amd-<ROCM_VERSION>-<ARCH_STRING>` and tags it `<VERSION>` plus `latest`. The image version (`VERSION` in `conf/build-config.env`) **iterates when Dockerfile.rocm changes**, and the change **increments its last component** (`1.1.0` to `1.1.1`). Changes to configuration files alone do not iterate it; the axis versions in the image name already distinguish those images.

## Building locally

Build prerequisites, the build procedure, the resulting image, and the test suites live in the [local build guide](docs/local-build-guide.md). It is the single home for build instructions; this guide does not repeat them.

## Running the tests

Run the suites from the repository root with `bash tests/<file>.sh`. The build suites need docker; the argument suite needs no daemon. The guide's Tests section lists every suite and what each one needs.

## Pull requests

Keep a pull request to one logical change, reference the issue it addresses in the description, and make sure the relevant suites pass before requesting review. A pull request adding configuration files for a new combination must name its add-support issue.
```

Note the exact test-matched phrases in place: `docs/local-build-guide.md`, `bug, enhancement, infrastructure and add-targets`, `[label]/issue-[#]-[short-description-kebab-case]`, `--arch-env`, `--rocm-env`, `--config-env`, `must name an add-support request issue that already exists`, `The image name follows the axis versions`, `iterates when Dockerfile.rocm changes`, `increments its last component`.

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test_contributing.sh`

Expected: all checks `ok`, `=== N passed, 0 failed ===`, exit status 0. (The guide links `docs/local-build-guide.md`, which does not exist until Task 6; the link target's existence is asserted there, per the spec scenario's combined check.)

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md tests/test_contributing.sh
git commit -m "Add the contribution guide

- Documents the six issue forms and labels, the branch naming standard,
  the issue-before-PR gate, the process for submitting new axes and
  combinations, and the two versioning conditions
- Links the local build guide rather than restating build instructions
- Adds a bash suite pinning every mandated policy phrase"
```

---

### Task 6: Local build guide, README split, and link tests

**Spec scenarios:** "The local build guide is linked from README and CONTRIBUTING" (both halves plus the file exists) and "README no longer carries the moved build sections".

**Files:**
- Create: `docs/local-build-guide.md`
- Modify: `README.md` (remove the four moved sections; add links)
- Create: `tests/test_docs.sh`

**Interfaces:**
- Consumes: README's `## Prerequisites`, `## Building` (including `### The resulting image`), and `## Tests` sections, moved verbatim; `CONTRIBUTING.md` from Task 5.
- Produces: `bash tests/test_docs.sh`; README keeps the overview and the config-file/axes reference tables and gains links to the guide and CONTRIBUTING.

- [ ] **Step 1: Write the failing test**

Create `tests/test_docs.sh`:

````bash
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
    if grep -qxF -- "$heading" "$BUILD_GUIDE"; then note_pass "guide carries: $heading"
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
````

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_docs.sh`

Expected: every check reports `FAIL` except the CONTRIBUTING half of the link check, which already passes from Task 5 (guide missing, README still carrying sections, no README links); exit status non-zero.

- [ ] **Step 3: Create the build guide**

Create `docs/local-build-guide.md`: a `# Local build guide` title, then README's `## Prerequisites`, `## Building` (with `### The resulting image` inside it), and `## Tests` sections moved verbatim. In the moved `## Tests` section, extend the list of suites and their descriptions with the three new ones, for example:

```markdown
`test_issue_forms.sh` verifies the six issue forms in `.github/ISSUE_TEMPLATE/`: chooser-valid front matter, the mandated required fields, the free-text axes and runtime fields, the log file uploads, and each add-support form's gate acknowledgement. It parses the forms' fixed YAML layout with grep and awk and needs no network or docker.

`test_contributing.sh` checks CONTRIBUTING.md for every mandated policy phrase: the labels, the branch naming standard, the issue-before-PR gate, the new-axes process, and the versioning conditions.

`test_docs.sh` checks the documentation split: the build sections live only in this guide, README and CONTRIBUTING link here, and this Tests section lists every suite.
```

- [ ] **Step 4: Split the README**

In `README.md`: delete the `## Prerequisites`, `## Building` (including `### The resulting image`), and `## Tests` sections, and add two short sections in their place, before `## License`:

```markdown
## Building locally

Prerequisites, the build procedure, the resulting image, and the test suites are covered in the [local build guide](docs/local-build-guide.md).

## Contributing

Bug reports, feature requests and add-support requests go through the issue forms; the full workflow — labels, branch naming, new build targets, versioning — is documented in [CONTRIBUTING.md](CONTRIBUTING.md).
```

Keep the overview and the Build config files / Architectures / ROCm releases / Neutral axis tables exactly as they are.

- [ ] **Step 5: Run it to verify it passes, and re-run the other suites**

Run: `bash tests/test_docs.sh` — expected all checks `ok`, `=== N passed, 0 failed ===`, exit status 0.

Run: `bash tests/test_issue_forms.sh && bash tests/test_contributing.sh` — expected both still fully green (nothing in Tasks 1–5 referenced the moved README sections).

Run: `bash tests/test_build_args.sh` — expected still green; the existing suite reads `conf/` and `build-rocm.sh`, untouched by this work. The docker-dependent suites (`test_build_stage.sh`, `test_runtime_stage.sh`) are not run here; this work changes no build inputs, and the runtime suite needs an AMD GPU.

- [ ] **Step 6: Commit**

```bash
git add docs/local-build-guide.md README.md tests/test_docs.sh
git commit -m "Extract the local build guide from the README

- Moves prerequisites, the build procedure, the resulting image and the test
  suites to docs/local-build-guide.md, the single home for build instructions
- README keeps the overview and reference tables, and links the build guide
  and CONTRIBUTING
- The guide's Tests section lists the three new suites; adds test_docs.sh
  pinning the split and the links"
```

- [ ] **Step 7: Post-merge note (not a commit)**

The forms become visible in the new-issue chooser only once this branch merges to the default branch (GitHub serves issue forms from the default branch). After the merge, open the repository's new-issue page and confirm the chooser lists the six forms in order with blank issues still available — the only acceptance step no local test can perform.
