# Issue Forms, Contribution Guide, and Local Build Guide — Design

Date: 2026-10-28

## Intent

Standardize issue intake and write down the contribution workflow for llama.cpp-rocm-docker. The repo currently has no issue templates and no CONTRIBUTING file, so the rule "a support issue must exist before a PR merging config files for that combination" has no home, and issue reports arrive in whatever shape the reporter chooses.

## Goals

- Four YAML issue forms in `.github/ISSUE_TEMPLATE/`:
  1. Platform bug — bug against a specific ROCm / GPU / Arch / llama.cpp combination
  2. General bug — bug not tied to a particular combination
  3. Feature request — not tied to a particular combination
  4. Support request — new platform combination, with evidence and the issue-before-PR rule
- `CONTRIBUTING.md` in the repo root: full contribution guide (scope B), including the process for submitting new axes for the build
- A separate local build guide, linked from both README and CONTRIBUTING, as the single home for local build instructions

## Non-goals

- No dropdowns or enumerated axis options — free text for now (possible later)

  **Platform forms accept free-text axes**
  ```gherkin
  Scenario: Platform bug form accepts free-text axis values
    Given the platform bug form
    When a contributor enters ROCm "9.9.9", GPU "gfx9999", Arch "TESTARCH" and llama.cpp version "v9.9.9", none of which exist in conf/
    Then the form accepts those values instead of offering a fixed choice list
  ```

- No `.github/ISSUE_TEMPLATE/config.yml`; blank issues stay available

  **Blank issues remain available**
  ```gherkin
  Scenario: Blank issues stay available alongside the forms
    Given the ISSUE_TEMPLATE directory contains no config.yml
    When a contributor opens the new issue chooser
    Then the blank issue option is still offered
  ```

- No automation enforcing the issue-before-PR gate — documented, not enforced
- No pull request template, code of conduct, or security policy

## Constraints

- GitHub issue forms must be `.yml` files in `.github/ISSUE_TEMPLATE/` with valid `name:` and `description:` keys ([Issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository#creating-issue-forms))
- A template `name:` must be more than 3 characters or the form is not shown ([Issue forms, note under "Creating issue templates"](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository))

  **Chooser-valid front matter on every form**
  ```gherkin
  Scenario: Every form carries front matter the chooser accepts
    Given the four files in .github/ISSUE_TEMPLATE
    When the template chooser loads them
    Then each file declares a name of more than three characters and a description
  ```

- CONTRIBUTING may live in root, `docs/`, or `.github/`; GitHub surfaces it on new-issue and new-PR pages ([Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors))
- Markdown filenames in kebab-case
- Issue forms must land on the default branch to be active

## Approaches considered

| # | Approach | Tradeoff | Outcome |
|---|----------|----------|---------|
| 1 | Narrow CONTRIBUTING (workflow only) | Lean, but leaves no full guide | Rejected — user chose scope B |
| 2 | Full CONTRIBUTING duplicating README build detail | Complete entry point, but two copies of build instructions drift | Rejected |
| 3 | Full CONTRIBUTING + extracted local build guide linked from both | One home for build detail; both docs point at it | **Chosen** (user's decision) |

Axis field style: dropdowns listing current `conf/` combinations would enforce consistency but go stale as configs land; free-text accepts any combination with no upkeep. **Free text** (user's decision, "for now").

## Decisions

From the user:

- Free-text `input`/`textarea` fields for the four axes (ROCm, GPU, Arch, llama.cpp version) on both platform-scoped forms

  **Axes are required on the platform bug form**
  ```gherkin
  Scenario: Platform bug form rejects a submission missing an axis
    Given the platform bug form
    When a contributor submits it with the llama.cpp version field empty
    Then the submission is blocked and llama.cpp version is marked required
  ```

- Both bug forms must require: symptoms, user runtime details (OS, Docker runtime, Docker version, etc.), steps to reproduce, logs

  **Both bug forms enforce the mandated report fields**
  ```gherkin
  Scenario: General bug form rejects a submission without logs
    Given the general bug form
    When a contributor submits it with symptoms, runtime details and reproduction steps filled but logs empty
    Then the submission is blocked and logs is marked required
  ```

  ```gherkin
  Scenario: Platform bug form rejects a submission without symptoms
    Given the platform bug form
    When a contributor submits it with runtime details, reproduction steps and logs filled but symptoms empty
    Then the submission is blocked and symptoms is marked required
  ```

  ```gherkin
  Scenario: A complete bug report is accepted on both bug forms
    Given the general bug form and the platform bug form
    When a contributor fills symptoms, runtime details, reproduction steps and logs
    Then both forms accept the submission because all four mandated fields are present and required
  ```

- Feature form must require: detailed description, what it improves, at least one implementation suggestion

  **Feature form enforces its three mandated fields**
  ```gherkin
  Scenario: Feature request rejects a submission without an implementation suggestion
    Given the feature request form
    When a contributor submits it with description and improvement filled but implementation suggestion empty
    Then the submission is blocked and implementation suggestion is marked required
  ```

  ```gherkin
  Scenario: A complete feature request is accepted
    Given the feature request form
    When a contributor fills description, what it improves and at least one implementation suggestion
    Then the form accepts the submission because all three mandated fields are present and required
  ```

- Support form must require: the four axes, evidence as llama.cpp logs run with the verbose flag showing startup on the target platform, and an acknowledgement of the issue-before-PR rule

  **Support form enforces axes, evidence and acknowledgement**
  ```gherkin
  Scenario: Support request rejects a submission missing an axis
    Given the support request form
    When a contributor submits it with the GPU field empty
    Then the submission is blocked and GPU is marked required
  ```

  ```gherkin
  Scenario: Support request rejects a submission without evidence
    Given the support request form
    When a contributor submits it with every field except the evidence log filled
    Then the submission is blocked and evidence is marked required
  ```

  ```gherkin
  Scenario: Support request rejects a submission without acknowledgement
    Given the support request form
    When a contributor submits it with the issue-before-PR acknowledgement unchecked
    Then the submission is blocked because the acknowledgement option is required
  ```

  ```gherkin
  Scenario: A complete support request with verbose startup evidence is accepted
    Given the support request form
    When a contributor fills the four axes, attaches llama-server startup logs produced with the verbose flag, and checks the acknowledgement
    Then the form accepts the submission
  ```

- CONTRIBUTING is scope B and must outline the process for submitting new axes

  **CONTRIBUTING carries the issue-before-PR gate and the new-axes process**
  ```gherkin
  Scenario: CONTRIBUTING states the issue-before-PR gate
    Given CONTRIBUTING.md at the repository root
    When a contributor plans a pull request adding conf files for a new combination
    Then CONTRIBUTING states that a support request issue must exist before that pull request is opened
  ```

  ```gherkin
  Scenario: CONTRIBUTING outlines how to submit new axes
    Given CONTRIBUTING.md at the repository root
    When a contributor reads the section on submitting new axes
    Then it lists the three config files (--arch-env, --rocm-env, --config-env) and the support issue that must precede the pull request
  ```

- Build instructions live in a separate local build guide linked from README and CONTRIBUTING

  **The build guide is linked from both documents**
  ```gherkin
  Scenario: The local build guide is linked from README and CONTRIBUTING
    Given README.md and CONTRIBUTING.md
    When a reader looks for the build guide reference in each
    Then both contain a link to docs/local-build-guide.md and the file exists
  ```

- Valid issue labels: `bug`, `enhancement`, `infrastructure`, `add-targets`

  **CONTRIBUTING documents the valid label set**
  ```gherkin
  Scenario: CONTRIBUTING lists all four valid labels
    Given CONTRIBUTING.md at the repository root
    When a contributor checks which labels issues may carry
    Then CONTRIBUTING names bug, enhancement, infrastructure and add-targets
  ```

My calls:

- Filenames with number prefixes to fix chooser order: `01-bug-report.yml`, `02-bug-report-platform.yml`, `03-feature-request.yml`, `04-support-request.yml`

  **Chooser order follows the numeric prefixes**
  ```gherkin
  Scenario: The chooser lists the forms in numeric order
    Given the four form files in .github/ISSUE_TEMPLATE
    When the template chooser renders them
    Then they appear as general bug, platform bug, feature request, support request
  ```

- Title prefixes `[Bug]: `, `[Feature]: `, `[Support]: `
- Form label defaults: `bug` on both bug forms, `enhancement` on the feature form, `add-targets` on the support form; `infrastructure` is applied by maintainers during triage and is available to blank issues, so no form carries it by default

  **Each form applies its assigned label and title prefix**
  ```gherkin
  Scenario: Bug forms apply the bug label and title prefix
    Given the general bug form and the platform bug form
    When an issue is created from either
    Then it carries the label bug and the title begins with "[Bug]: "
  ```

  ```gherkin
  Scenario: The feature form applies the enhancement label and title prefix
    Given the feature request form
    When an issue is created from it
    Then it carries the label enhancement and the title begins with "[Feature]: "
  ```

  ```gherkin
  Scenario: The support form applies the add-targets label and title prefix
    Given the support request form
    When an issue is created from it
    Then it carries the label add-targets and the title begins with "[Support]: "
  ```

- Build guide at `docs/local-build-guide.md` (kebab-case, `docs/` alongside existing project docs)
- README split: Prerequisites, Building, The resulting image, and Tests move to the build guide; README keeps the overview and the config-file/axes reference tables, and links to the build guide and CONTRIBUTING

  **Build instructions live only in the guide after the split**
  ```gherkin
  Scenario: README no longer carries the moved build sections
    Given README.md after the split
    When a reader searches README for the build procedure
    Then README contains neither the Prerequisites, Building, The resulting image nor Tests sections, and docs/local-build-guide.md contains all four
  ```

- `CONTRIBUTING.md` at the repo root
- No `config.yml` and no PR template

## Versioning and branch naming

From the user:

- The image name continues to follow the versions from the axes, exactly as today: `build-rocm.sh` composes `REGISTRY/agenticsnz/llama.cpp-<LLAMA_CPP_VERSION>-amd-<ROCM_VERSION>-<ARCH_STRING>` and tags it `<VERSION>` plus `latest`
- The image version (`VERSION` in `conf/build-config.env`) iterates when `Dockerfile.rocm` changes; CONTRIBUTING states both conditions

  **CONTRIBUTING states the two versioning conditions**
  ```gherkin
  Scenario: CONTRIBUTING documents the versioning conditions
    Given CONTRIBUTING.md at the repository root
    When a contributor reads the versioning section
    Then it states that the image name follows the axis versions and that VERSION iterates when Dockerfile.rocm changes
  ```

- Branch names follow `[label]/issue-[#]-[short-description-kebab-case]`

  **CONTRIBUTING states the branch naming standard**
  ```gherkin
  Scenario: CONTRIBUTING documents the branch naming format
    Given CONTRIBUTING.md at the repository root
    When a contributor reads the branch naming section
    Then it states the format [label]/issue-[#]-[short-description-kebab-case] with the four valid labels as [label]
  ```

My calls:

- `VERSION` increments its last component (`1.1.0` → `1.1.1`)
- `[label]` is the issue's applied label, one of `bug`, `enhancement`, `infrastructure`, `add-targets`
- `[short-description-kebab-case]` is 3-5 kebab-case words derived from the issue title, e.g. `bug/issue-42-container-toolkit-not-detected` or `add-targets/issue-88-add-gfx90a-target`
- Every branch names an issue, so an issue exists before branching — which also covers the support issue-before-PR gate

Scope decision:

- Document the trigger verbatim: `VERSION` iterates when `Dockerfile.rocm` changes, and the image name follows the axis versions as it does today. Externalising `VERSION` from `conf/build-config.env` is acknowledged as needed but is part of a separate issue and out of scope here; the same-tag overwrite case raised against this rule is deferred to that issue.

## What's left to the builder

- Exact field wording and structure of each form per GitHub's form schema
- CONTRIBUTING and build guide section prose
- Link edits in README
