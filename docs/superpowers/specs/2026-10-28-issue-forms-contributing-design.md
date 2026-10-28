# Issue Forms, Contribution Guide, and Local Build Guide — Design

Date: 2026-10-28

## Intent

Standardize issue intake and write down the contribution workflow for
llama.cpp-rocm-docker. The repo currently has no issue templates and no
CONTRIBUTING file, so the rule "a support issue must exist before a PR
merging config files for that combination" has no home, and issue reports
arrive in whatever shape the reporter chooses.

## Goals

- Four YAML issue forms in `.github/ISSUE_TEMPLATE/`:
  1. Platform bug — bug against a specific ROCm / GPU / Arch / llama.cpp combination
  2. General bug — bug not tied to a particular combination
  3. Feature request — not tied to a particular combination
  4. Support request — new platform combination, with evidence and the issue-before-PR rule
- `CONTRIBUTING.md` in the repo root: full contribution guide (scope B),
  including the process for submitting new axes for the build
- A separate local build guide, linked from both README and CONTRIBUTING,
  as the single home for local build instructions

## Non-goals

- No dropdowns or enumerated axis options — free text for now (possible later)
- No `.github/ISSUE_TEMPLATE/config.yml`; blank issues stay available
- No automation enforcing the issue-before-PR gate — documented, not enforced
- No pull request template, code of conduct, or security policy

## Constraints

- GitHub issue forms must be `.yml` files in `.github/ISSUE_TEMPLATE/` with
  valid `name:` and `description:` keys
  ([Issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository#creating-issue-forms))
- CONTRIBUTING may live in root, `docs/`, or `.github/`; GitHub surfaces it
  on new-issue and new-PR pages
  ([Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors))
- Markdown filenames in kebab-case
- Issue forms must land on the default branch to be active

## Approaches considered

| # | Approach | Tradeoff | Outcome |
|---|----------|----------|---------|
| 1 | Narrow CONTRIBUTING (workflow only) | Lean, but leaves no full guide | Rejected — user chose scope B |
| 2 | Full CONTRIBUTING duplicating README build detail | Complete entry point, but two copies of build instructions drift | Rejected |
| 3 | Full CONTRIBUTING + extracted local build guide linked from both | One home for build detail; both docs point at it | **Chosen** (user's decision) |

Axis field style: dropdowns listing current `conf/` combinations would enforce
consistency but go stale as configs land; free-text accepts any combination
with no upkeep. **Free text** (user's decision, "for now").

## Decisions

From the user:

- Free-text `input`/`textarea` fields for the four axes (ROCm, GPU, Arch,
  llama.cpp version) on both platform-scoped forms
- Both bug forms must require: symptoms, user runtime details (OS, Docker
  runtime, Docker version, etc.), steps to reproduce, logs
- Feature form must require: detailed description, what it improves, at least
  one implementation suggestion
- Support form must require: the four axes, evidence as llama.cpp logs run
  with the verbose flag showing startup on the target platform, and an
  acknowledgement of the issue-before-PR rule
- CONTRIBUTING is scope B and must outline the process for submitting new
  axes
- Build instructions live in a separate local build guide linked from README
  and CONTRIBUTING
- Valid issue labels: `bug`, `enhancement`, `infrastructure`, `add-targets`

My calls (not yet agreed):

- Filenames with number prefixes to fix chooser order:
  `01-bug-report.yml`, `02-bug-report-platform.yml`,
  `03-feature-request.yml`, `04-support-request.yml`
- Title prefixes `[Bug]: `, `[Feature]: `, `[Support]: `
- Form label defaults: `bug` on both bug forms, `enhancement` on the feature
  form, `add-targets` on the support form; `infrastructure` is applied by
  maintainers during triage and is available to blank issues, so no form
  carries it by default
- Build guide at `docs/local-build-guide.md` (kebab-case, `docs/` alongside
  existing project docs)
- README split: Prerequisites, Building, The resulting image, and Tests move
  to the build guide; README keeps the overview and the config-file/axes
  reference tables, and links to the build guide and CONTRIBUTING
- `CONTRIBUTING.md` at the repo root
- No `config.yml` and no PR template

## Versioning and branch naming

From the user:

- The image name continues to follow the versions from the axes, exactly as
  today: `build-rocm.sh` composes
  `REGISTRY/agenticsnz/llama.cpp-<LLAMA_CPP_VERSION>-amd-<ROCM_VERSION>-<ARCH_STRING>`
  and tags it `<VERSION>` plus `latest`
- The image version (`VERSION` in `conf/build-config.env`) iterates when
  `Dockerfile.rocm` changes; CONTRIBUTING states both conditions
- Branch names follow `[label]/issue-[#]-[short-description-kebab-case]`

My calls:

- `VERSION` increments its last component (`1.1.0` → `1.1.1`)
- `[label]` is the issue's applied label, one of `bug`, `enhancement`,
  `infrastructure`, `add-targets`
- `[short-description-kebab-case]` is 3-5 kebab-case words derived from the
  issue title, e.g. `bug/issue-42-container-toolkit-not-detected` or
  `add-targets/issue-88-add-gfx90a-target`
- Every branch names an issue, so an issue exists before branching — which
  also covers the support issue-before-PR gate

Open question:

- Whether a content change to `conf/*.env` or `build-rocm.sh` at unchanged
  axis versions also bumps `VERSION`. Under the stated rule the name and the
  version both stay identical, so the next build would overwrite an
  already-published versioned tag with different contents.

## What's left to the builder

- Exact field wording and structure of each form per GitHub's form schema
- CONTRIBUTING and build guide section prose
- Link edits in README
