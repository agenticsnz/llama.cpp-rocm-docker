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
  release_manifest_tool.sh --get release_version
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
    # Returns 0 when $1 is one of $AXES.
    case " $AXES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_release_version() {
    # Returns 0 when $1 matches MAJOR.MINOR.PATCH with digits only.
    return 1
}

read_release_version() {
    # yq -r '.release_version' "$MANIFEST"
    return 1
}

write_release_version() {
    # V="<value>" yq -i '.release_version = strenv(V)' "$MANIFEST"
    return 1
}

list_axis_values() {
    # yq -r '.support.<axis>[]' "$MANIFEST"
    return 1
}

add_axis_value() {
    # Checks: value not already in the list; "$CONF_DIR/<value>.env" exists.
    # V="<value>" yq -i '.support.<axis> += [strenv(V)]' "$MANIFEST"
    return 1
}

delete_axis_value() {
    # Checks: value is in the list.
    # V="<value>" yq -i '.support.<axis> |= del(.[] | select(. == strenv(V)))' "$MANIFEST"
    return 1
}

# Each arm is "checks && is_valid || usage_error": the || is the intended exit path.
# shellcheck disable=SC2015
main() {
    case "${1:-}" in
        --get)    [ "$#" -eq 2 ] && [ "$2" = release_version ] || usage_error "--get takes release_version"
                  read_release_version ;;
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
