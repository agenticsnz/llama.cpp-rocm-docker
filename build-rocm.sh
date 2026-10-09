#!/usr/bin/env bash
# Build the llama.cpp ROCm image from three configuration files.
#
# Each configuration file owns one axis of the build. The architecture file
# owns anything that changes with the card, the ROCm version file owns anything
# that changes with the release, and the axis-neutral file owns the rest. A key
# appearing in more than one file resolves to the file that owns its axis; the
# other copy is reported and discarded, so a stray duplicate cannot silently
# change the build.
#
# Filename mismatches warn rather than fail, because a multi-architecture file
# legitimately names one target and carries several. Genuine errors — an
# unreadable file, a missing required key, a bad invocation — are fatal and say
# which file and which key caused them.
#
# The --dry-run mode prints the resolved arguments and exits without invoking
# docker, so the ownership and warning rules can be tested without paying a
# build per case.
set -uo pipefail

# Path of the file that owns each axis, assigned during argument parsing.
ARCH_ENV_FILE=''
ROCM_ENV_FILE=''
CONFIG_ENV_FILE=''
SOURCE_DIR=''
DRY_RUN='no'
NO_CACHE='no'

# Resolved absolute paths of the three files, so ownership compares like with like.
ARCH_ENV_PATH=''
ROCM_ENV_PATH=''
CONFIG_ENV_PATH=''

# Directory holding this script, so the build can reference our Dockerfile.rocm
# by absolute path while the build context stays the llama.cpp source tree.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Key to owning axis. A key absent from this map is not axis-specific, so it is
# treated as neutral and passed through whichever file set it.
declare -A KEY_AXIS=(
    [GPU_TARGET]=arch
    [ARCH_STRING]=arch
    [GGML_CUDA_FA_QUANTS]=arch
    [ROCM_BASE]=rocm
    [ROCM_VERSION]=rocm
    [ROCM_BASE_ASSEMBLY]=rocm
    [ROCM_CORE_DIR]=rocm
    [LD_LIBRARY_PATH]=rocm
    [CMAKE_BUILD_TYPE]=neutral
    [REGISTRY]=neutral
    [LLAMA_CPP_VERSION]=neutral
    [VERSION]=neutral
    [GGML_NATIVE]=neutral
)

# Every key the build cannot proceed without, since the image reference or the
# compiler target depends on each.
declare -a REQUIRED_KEYS=(
    REGISTRY LLAMA_CPP_VERSION VERSION
    GPU_TARGET ARCH_STRING
    ROCM_BASE ROCM_VERSION ROCM_CORE_DIR
)

# Every file's own reading of every key, keyed by "<absolute path>|<KEY>".
# Keeping all three files' values is what lets ownership pick the owning file's
# value rather than whichever file happened to be read first.
declare -A FILE_VALUE=()

# Command-line overrides from repeatable --set KEY=VALUE flags, keyed by key.
# Later occurrences overwrite earlier ones, so the last --set for a key wins.
declare -A CLI_VALUE=()

# Keys whose pre-CLI value was adopted from the exported shell environment.
# Lets the CLI-override warning name the shell origin when no file copy exists.
declare -A SHELL_ADOPTED=()

# Surviving values after ownership is applied.
declare -A RESOLVED_VALUE=()

# Image reference components, fixed by this project's naming scheme.
readonly IMAGE_LABEL_ROOT='agenticsnz'
readonly IMAGE_REPOSITORY_NAME='llama.cpp'
readonly TAG_LATEST='latest'

# Parsing helpers, kept as named patterns so the intent reads at each use.
readonly ASSIGNMENT_SEPARATOR='='
readonly COMMENT_PREFIX='#'
readonly BLANK_PATTERN='^[[:space:]]*$'
readonly ARCH_TOKEN_PATTERN='^amd-gfx[0-9a-z]*$'
readonly VERSION_TOKEN_PATTERN='^amd-[0-9][0-9.]*$'
readonly BASE_TAG_PATTERN='.*:([0-9][0-9.]*)(-[a-z-]*)$'
readonly ARCH_TOKEN_PREFIX='amd-'
readonly VERSION_TOKEN_PREFIX='amd-'

USAGE_MESSAGE="usage: $(basename "$0") --arch-env <path> --rocm-env <path> --config-env <path> --source <path> [--dry-run] [--no-cache] [--set KEY=VALUE ...]"

die() {
    printf '%s: %s\n' "$(basename "$0")" "$1" >&2
    exit 2
}

warn() {
    printf '%s: warning: %s\n' "$(basename "$0")" "$1" >&2
}

# Report the axis that owns a key, or neutral when the key is not axis-specific.
# Reads KEY_AXIS, which is populated once at load time and never mutated, so a
# lookup is total and needs no failure branch.
axis_owning() {
    local key="$1"
    printf '%s' "${KEY_AXIS[$key]:-neutral}"
}

# Report the path of the file that owns an axis. Callers pass one of arch, rocm
# or neutral, which are the only values KEY_AXIS can hold.
file_owning_axis() {
    case "$1" in
        arch)    printf '%s' "$ARCH_ENV_PATH" ;;
        rocm)    printf '%s' "$ROCM_ENV_PATH" ;;
        neutral) printf '%s' "$CONFIG_ENV_PATH" ;;
        *)       die "internal error: unknown ownership axis '$1'." ;;
    esac
}

# Load KEY=VALUE lines from one configuration file into the per-file store.
# Blank lines, comments and lines without a separator are skipped. Every file
# keeps its own reading of every key so that ownership, applied afterwards, can
# choose the value from the file that owns the key's axis.
load_configuration_file() {
    local file_path="$1" line key value
    [ -r "$file_path" ] || die "cannot read configuration file '$file_path': build arguments are resolved from these files, so an unreadable one is fatal rather than skipped."
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ "$line" =~ $BLANK_PATTERN ]] && continue
        [[ "$line" == "$COMMENT_PREFIX"* ]] && continue
        [[ "$line" == *"$ASSIGNMENT_SEPARATOR"* ]] || continue
        key="${line%%"$ASSIGNMENT_SEPARATOR"*}"
        value="${line#*"$ASSIGNMENT_SEPARATOR"}"
        key="${key//[[:space:]]/}"
        [ -z "$key" ] && continue
        FILE_VALUE["$file_path|$key"]="$value"
    done < "$file_path"
}

# Report a key's value as read by one file, or empty when that file omits it.
value_from_file() {
    local file_path="$1" key="$2"
    printf '%s' "${FILE_VALUE[$file_path|$key]:-}"
}

# Resolve the candidate set down to the values the build will use.
# For each key the owning axis decides the winning file; a duplicate found
# elsewhere is reported naming the key and the file that lost, then discarded.
apply_ownership() {
    local key axis owner_path owner_value other_path other_value
    for key in "${!FILE_VALUE[@]}"; do
        key="${key#*|}"
        [ -n "${RESOLVED_VALUE[$key]:-}" ] && continue
        axis="$(axis_owning "$key")"
        owner_path="$(file_owning_axis "$axis")"
        owner_value="$(value_from_file "$owner_path" "$key")"
        for other_path in "${ARCH_ENV_PATH}" "${ROCM_ENV_PATH}" "${CONFIG_ENV_PATH}"; do
            [ "$other_path" = "$owner_path" ] && continue
            other_value="$(value_from_file "$other_path" "$key")"
            [ -z "$other_value" ] && continue
            warn "key $key is set in '$other_path', which does not own the $axis axis. '$owner_path' wins, so that copy is discarded."
        done
        if [ -n "$owner_value" ]; then
            RESOLVED_VALUE["$key"]="$owner_value"
        else
            # The owning file omits this key, so the value is not axis-specific
            # after all and whichever file supplied it is used.
            RESOLVED_VALUE["$key"]="$(value_from_file "${ARCH_ENV_PATH}" "$key")"
            [ -n "${RESOLVED_VALUE[$key]}" ] || RESOLVED_VALUE["$key"]="$(value_from_file "${ROCM_ENV_PATH}" "$key")"
            [ -n "${RESOLVED_VALUE[$key]}" ] || RESOLVED_VALUE["$key"]="$(value_from_file "${CONFIG_ENV_PATH}" "$key")"
        fi
    done
}

# Adopt exported shell values for known keys that no file set. Only keys in
# REQUIRED_KEYS or KEY_AXIS are considered, so arbitrary exports never leak
# into the build; empty exports count as unset. Each adoption is reported
# naming the key, consistent with the other resolution warnings. Runs after
# file ownership and before CLI overrides, so files beat the shell and --set
# beats both. Indirect expansion uses the :- default so unset names are safe
# under set -u.
apply_shell_fallback() {
    local key shell_value
    declare -A seen_keys=()
    for key in "${REQUIRED_KEYS[@]}" "${!KEY_AXIS[@]}"; do
        [ -n "${seen_keys[$key]:-}" ] && continue
        seen_keys["$key"]=1
        [ -n "${RESOLVED_VALUE[$key]:-}" ] && continue
        shell_value="${!key:-}"
        [ -n "$shell_value" ] || continue
        RESOLVED_VALUE["$key"]="$shell_value"
        SHELL_ADOPTED["$key"]=1
        warn "key $key is absent from all three configuration files, so the exported shell value is used. Set it in a file or via --set to silence this."
    done
}

# Apply command-line --set overrides onto the resolved values. For each --set
# key the CLI value wins: when the files resolved a different value that value
# is reported naming the key and the losing files, then discarded. Previously
# unseen keys pass through unchanged, and identical values stay silent. An
# empty --set value counts as absent, so it neither displaces a resolved value
# nor appears in the emitted arguments.
apply_cli_overrides() {
    local key cli_value resolved_value file_path file_value losing_files
    for key in "${!CLI_VALUE[@]}"; do
        cli_value="${CLI_VALUE[$key]:-}"
        [ -n "$cli_value" ] || continue
        resolved_value="${RESOLVED_VALUE[$key]:-}"
        if [ -n "$resolved_value" ] && [ "$resolved_value" != "$cli_value" ]; then
            losing_files=""
            for file_path in "$ARCH_ENV_PATH" "$ROCM_ENV_PATH" "$CONFIG_ENV_PATH"; do
                file_value="$(value_from_file "$file_path" "$key")"
                [ -n "$file_value" ] || continue
                losing_files="$losing_files '$file_path'"
            done
            if [ -n "$losing_files" ]; then
                warn "key $key is set on the command line via --set, overriding$losing_files. The CLI value wins, so those copies are discarded."
            elif [ -n "${SHELL_ADOPTED[$key]:-}" ]; then
                warn "key $key is set on the command line via --set, overriding the exported shell value. The CLI value wins, so that copy is discarded."
            else
                warn "key $key is set on the command line via --set, overriding$losing_files. The CLI value wins, so those copies are discarded."
            fi
        fi
        RESOLVED_VALUE["$key"]="$cli_value"
    done
}

# Reject a build that would produce a wrong image silently. A missing key is
# fatal here rather than warned about, because the resulting image reference or
# compiler target would be wrong in a way that is not obvious until it runs.
require_keys_present() {
    local required_key
    for required_key in "${REQUIRED_KEYS[@]}"; do
        [ -n "${RESOLVED_VALUE[$required_key]:-}" ] || \
            die "required key $required_key is absent after reading configuration files, shell fallback, and --set overrides. The image reference or compiler target depends on it, so the build cannot proceed without it."
    done
}

# Warn when an architecture file names one target and compiles for another.
# This is legitimate for a multi-architecture file, so it is never fatal.
warn_if_arch_filename_disagrees() {
    local file_path="$1" targets="$2" named_token
    named_token="$(basename "$file_path" .env)"
    [[ "$named_token" =~ $ARCH_TOKEN_PATTERN ]] || return 0
    named_token="${named_token#"$ARCH_TOKEN_PREFIX"}"
    [ "$targets" = "$named_token" ] && return 0
    warn "'$file_path' is named for architecture '$named_token' but sets GPU_TARGET='$targets'. A file may compile for several targets, so its contents are authoritative and this is not fatal."
}

# Warn when a version file's name disagrees with the version it declares.
# A base image is one specific release, so a mismatch here is a labelling
# defect worth reading even though the contents still win.
warn_if_version_filename_disagrees() {
    local file_path="$1" version="$2" named_token
    named_token="$(basename "$file_path" .env)"
    [[ "$named_token" =~ $VERSION_TOKEN_PATTERN ]] || return 0
    named_token="${named_token#"$VERSION_TOKEN_PREFIX"}"
    [ "$version" = "$named_token" ] && return 0
    warn "'$file_path' is named for ROCm $named_token but sets ROCM_VERSION=$version. The contents are authoritative and this is not fatal."
}

# Warn when ROCM_BASE names a different version than ROCM_VERSION declares.
# A disagreement here propagates into the image tag, so it is reported even
# though the build can still proceed.
warn_if_base_tag_disagrees() {
    local base_image="$1" version="$2" tagged_version
    [[ "$base_image" =~ $BASE_TAG_PATTERN ]] || return 0
    tagged_version="${BASH_REMATCH[1]}"
    [ "$tagged_version" = "$version" ] && return 0
    warn "ROCM_BASE='$base_image' carries version $tagged_version but ROCM_VERSION=$version. Confirm these agree before trusting the image tag."
}

run_consistency_checks() {
    warn_if_arch_filename_disagrees "$ARCH_ENV_PATH" "${RESOLVED_VALUE[GPU_TARGET]}"
    warn_if_version_filename_disagrees "$ROCM_ENV_PATH" "${RESOLVED_VALUE[ROCM_VERSION]}"
    warn_if_base_tag_disagrees "${RESOLVED_VALUE[ROCM_BASE]}" "${RESOLVED_VALUE[ROCM_VERSION]}"
}

# Compose the image reference from the resolved values. The registry's
# trailing slash is stripped so a default carrying one cannot produce a
# double slash in the reference.
build_image_reference() {
    printf '%s/%s/%s-%s-amd-%s-%s' \
        "${RESOLVED_VALUE[REGISTRY]%/}" \
        "$IMAGE_LABEL_ROOT" \
        "$IMAGE_REPOSITORY_NAME" \
        "${RESOLVED_VALUE[LLAMA_CPP_VERSION]}" \
        "${RESOLVED_VALUE[ROCM_VERSION]}" \
        "${RESOLVED_VALUE[ARCH_STRING]}"
}

# Emit one --build-arg line per resolved key, sorted so the output is stable
# and diffable between runs.
emit_resolved_arguments() {
    local key
    for key in $(printf '%s\n' "${!RESOLVED_VALUE[@]}" | sort); do
        printf -- '--build-arg %s%s%s\n' "$key" "$ASSIGNMENT_SEPARATOR" "${RESOLVED_VALUE[$key]}"
    done
}

# Emit the two tags the build publishes: the pinned version, which deployments
# reference, and latest, which is overwritten by the next build and is therefore
# a convenience reference rather than a pinnable one.
emit_tag_arguments() {
    local image_reference="$1"
    printf -- '--tag %s:%s\n' "$image_reference" "${RESOLVED_VALUE[VERSION]}"
    printf -- '--tag %s:%s\n' "$image_reference" "$TAG_LATEST"
}

parse_arguments() {
    local flag_name flag_value set_argument set_key set_value
    while [ $# -gt 0 ]; do
        case "$1" in
            --set)
                set_argument="${2:-}"
                [ -n "$set_argument" ] || die "--set requires a KEY=VALUE argument. $USAGE_MESSAGE"
                [[ "$set_argument" == *"$ASSIGNMENT_SEPARATOR"* ]] || die "invalid --set value '$set_argument': expected KEY=VALUE. $USAGE_MESSAGE"
                set_key="${set_argument%%"$ASSIGNMENT_SEPARATOR"*}"
                set_key="${set_key//[[:space:]]/}"
                [ -n "$set_key" ] || die "invalid --set value '$set_argument': key is empty. $USAGE_MESSAGE"
                set_value="${set_argument#*"$ASSIGNMENT_SEPARATOR"}"
                CLI_VALUE["$set_key"]="$set_value"
                shift 2
                ;;
            --arch-env|--rocm-env|--config-env|--source)
                flag_name="$1"
                flag_value="${2:-}"
                [ -n "$flag_value" ] || die "flag $flag_name requires a path. $USAGE_MESSAGE"
                case "$flag_name" in
                    --arch-env)   ARCH_ENV_FILE="$flag_value" ;;
                    --rocm-env)   ROCM_ENV_FILE="$flag_value" ;;
                    --config-env) CONFIG_ENV_FILE="$flag_value" ;;
                    --source)     SOURCE_DIR="$flag_value" ;;
                esac
                shift 2
                ;;
            --dry-run) DRY_RUN='yes'; shift ;;
            --no-cache) NO_CACHE='yes'; shift ;;
            -h|--help)   printf '%s\n' "$USAGE_MESSAGE"; exit 0 ;;
            *)           die "unrecognised argument '$1'. $USAGE_MESSAGE" ;;
        esac
    done
    [ -n "$ARCH_ENV_FILE" ]   || die "--arch-env was not supplied. $USAGE_MESSAGE"
    [ -n "$ROCM_ENV_FILE" ]   || die "--rocm-env was not supplied. $USAGE_MESSAGE"
    [ -n "$CONFIG_ENV_FILE" ] || die "--config-env was not supplied. $USAGE_MESSAGE"
    [ -n "$SOURCE_DIR" ]      || die "--source was not supplied. $USAGE_MESSAGE"
    [ -d "$SOURCE_DIR" ]      || die "source tree '$SOURCE_DIR' is not a directory. Pass the llama.cpp repository root, which the build copies whole as its context."
}

main() {
    parse_arguments "$@"

    ARCH_ENV_PATH="$(readlink -f "$ARCH_ENV_FILE")"
    ROCM_ENV_PATH="$(readlink -f "$ROCM_ENV_FILE")"
    CONFIG_ENV_PATH="$(readlink -f "$CONFIG_ENV_FILE")"

    load_configuration_file "$ARCH_ENV_PATH"
    load_configuration_file "$ROCM_ENV_PATH"
    load_configuration_file "$CONFIG_ENV_PATH"
    apply_ownership
    apply_shell_fallback
    apply_cli_overrides
    require_keys_present
    run_consistency_checks

    local image_reference
    image_reference="$(build_image_reference)"

    emit_resolved_arguments
    emit_tag_arguments "$image_reference"

    [ "$DRY_RUN" = 'yes' ] && return 0

    [ -f "$SOURCE_DIR/.devops/rocm.Dockerfile" ] || \
        die "'$SOURCE_DIR/.devops/rocm.Dockerfile' not found. The build context must be a llama.cpp checkout at a tag carrying .devops/rocm.Dockerfile, which the build copies whole."

    # The resolved keys match the ARG dialect of our Dockerfile.rocm
    # (ROCM_BASE, GPU_TARGET, ROCM_CORE_DIR, ...), not upstream's
    # .devops/rocm.Dockerfile (BASE_ROCM_DEV_CONTAINER, ROCM_DOCKER_ARCH).
    # Building upstream's file with these args derives a -complete base tag
    # that exists for no modern ROCm release, so this file is the only valid
    # -f target. It lives beside this script while the context is the
    # llama.cpp tree, hence the absolute -f with a separate context dir.
    local -a build_arguments=()
    local resolved_key
    for resolved_key in $(printf '%s\n' "${!RESOLVED_VALUE[@]}" | sort); do
        build_arguments+=(--build-arg "$resolved_key=${RESOLVED_VALUE[$resolved_key]}")
    done
    build_arguments+=(--tag "$image_reference:${RESOLVED_VALUE[VERSION]}")
    build_arguments+=(--tag "$image_reference:$TAG_LATEST")
    # Cache bypass sits with the other docker options, ahead of the -f flag
    # and the context path, which docker requires last.
    [ "$NO_CACHE" = 'yes' ] && build_arguments+=(--no-cache)
    build_arguments+=(-f "$SCRIPT_DIR/Dockerfile.rocm" "$SOURCE_DIR")

    docker build "${build_arguments[@]}" || die "docker build failed for '$image_reference'. The build log above names the failing step."
}

main "$@"
