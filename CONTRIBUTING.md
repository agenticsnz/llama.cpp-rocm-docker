# Contributing

Thank you for contributing. This guide covers issue intake, branch naming, adding new build targets, versioning, and the pull request process.

## Issue forms

Six issue forms are available in the new-issue chooser, each applying its label and a title prefix: a general bug report ([Bug]: , label bug) for problems not tied to a particular combination, a platform bug report ([Bug]: , label bug) for problems against a specific ROCm / GPU / architecture / llama.cpp combination, a feature request ([Feature]: , label enhancement), and three add-support forms for new build targets — add hardware support ([Add Hardware]: , label add-targets), add ROCm version ([Add ROCm]: , label add-targets) and add llama.cpp version ([Add llama.cpp]: , label add-targets). Blank issues remain available for anything that does not fit a form.

## Labels

Issues carry one of four labels: **bug, enhancement, infrastructure and add-targets**. The forms apply their own label; infrastructure is applied by maintainers during triage and is available to blank issues, so no form carries it by default.

## Branch naming

Branch names follow **[label]/issue-[#]-[short-description-kebab-case]**. `[label]` is the issue's applied label, one of bug, enhancement, infrastructure or add-targets. `[#]` is the issue number, and the short description is three to five kebab-case words derived from the issue title, for example `bug/issue-42-container-toolkit-not-detected`. Every branch names an issue, so an issue exists before any branch does.

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
