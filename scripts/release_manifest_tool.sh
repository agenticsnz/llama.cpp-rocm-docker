#!/usr/bin/env bash
# Reads and writes build-conf/project-release.yaml with yq v4.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
# MANIFEST is read by the yq calls that the stubs below will carry.
# shellcheck disable=SC2034
readonly MANIFEST="$REPO_ROOT/build-conf/project-release.yaml"
readonly CONF_DIR="${CONF_DIR:-$REPO_ROOT/conf}"
readonly AXES="llama-cpp amd-rocm amd-arch"

usage() {
    cat <<'EOF'
Usage:
  release_manifest_tool.sh --get <key>
  release_manifest_tool.sh --set release_version <value>
  release_manifest_tool.sh --list <axis>
  release_manifest_tool.sh --add <axis> <value>
  release_manifest_tool.sh --delete <axis> <value>
EOF
}

usage_error() {
    echo "$1" >&2
    usage >&2
    exit 2
}

check_failed() {
    echo "$1" >&2
    exit 1
}

is_axis() {
    # Returns 0 when $1 equals one whole word of $AXES.
    local axis
    for axis in $AXES; do
        [ "$axis" = "$1" ] && return 0
    done
    return 1
}

manifest_exists() {
    # Exits 1 naming the manifest when $MANIFEST is not a regular file.
    [ -f "$MANIFEST" ] || check_failed "missing manifest: $MANIFEST"
}

is_valid_release_version() {
    # Returns 0 when $1 matches MAJOR.MINOR.PATCH with digits only.
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

read_key() {
    # Prints the value of top-level scalar key $1; exits 1 naming the key when it is absent or not a scalar.
    manifest_exists
    local has_key tag
    has_key="$(K="$1" yq -r 'has(strenv(K))' "$MANIFEST")"
    [ "$has_key" = "true" ] || check_failed "key not found: $1"
    tag="$(K="$1" yq -r '.[strenv(K)] | tag' "$MANIFEST")"
    case "$tag" in
        '!!str' | '!!int' | '!!float' | '!!bool') ;;
        *) check_failed "key is not a single-value key: $1" ;;
    esac
    K="$1" yq -r '.[strenv(K)]' "$MANIFEST"
}

write_release_version() {
    manifest_exists
    is_valid_release_version "$1" || check_failed "invalid release_version: $1 (expected MAJOR.MINOR.PATCH)"
    # The style operator forces double quotes, which strenv alone keeps only when the old value was quoted.
    V="$1" yq -i '.release_version = strenv(V) | .release_version style = "double"' "$MANIFEST"
}

list_axis_values() {
    manifest_exists
    yq -r ".support.$1[]" "$MANIFEST"
}

axis_value_exists() {
    # Returns 0 when $2 is in the list for axis $1.
    manifest_exists
    V="$2" yq -e ".support.$1[] | select(. == strenv(V))" "$MANIFEST" >/dev/null 2>&1
}

env_file_exists() {
    # Returns 0 when "$CONF_DIR/$1.env" is a regular file.
    [ -f "$CONF_DIR/$1.env" ]
}

add_axis_value() {
    axis_value_exists "$1" "$2" && check_failed "already in $1: $2"
    env_file_exists "$2" || check_failed "no env file for $2: $CONF_DIR/$2.env"
    V="$2" yq -i ".support.$1 += [strenv(V)]" "$MANIFEST"
}

delete_axis_value() {
    manifest_exists
    axis_value_exists "$1" "$2" || check_failed "not in $1: $2"
    V="$2" yq -i ".support.$1 |= del(.[] | select(. == strenv(V)))" "$MANIFEST"
}

# Each arm is "checks && is_valid || usage_error": the || is the intended exit path.
# shellcheck disable=SC2015
main() {
    case "${1:-}" in
        --get)    [ "$#" -eq 2 ] || usage_error "--get takes one key name"
                  read_key "$2" ;;
        --set)    [ "$#" -eq 3 ] && [ "$2" = release_version ] || usage_error "--set takes release_version and a value"
                  write_release_version "$3" ;;
        --list)   [ "$#" -eq 2 ] && is_axis "$2" || usage_error "--list takes one axis name"
                  list_axis_values "$2" ;;
        --add)    [ "$#" -eq 3 ] && is_axis "$2" || usage_error "--add takes an axis name and a value"
                  add_axis_value "$2" "$3" ;;
        --delete) [ "$#" -eq 3 ] && is_axis "$2" || usage_error "--delete takes an axis name and a value"
                  delete_axis_value "$2" "$3" ;;
        *)        usage_error "missing or unknown command" ;;
    esac
}

main "$@"
