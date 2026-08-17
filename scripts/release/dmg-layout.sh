#!/usr/bin/env bash
set -euo pipefail

readonly RECORD_DMG_APP_NAME="Record.app"
readonly RECORD_DMG_APPLICATIONS_LINK_NAME="Applications"
readonly RECORD_DMG_APPLICATIONS_LINK_TARGET="/Applications"

validate_record_dmg_layout() {
    if [[ $# -ne 1 ]]; then
        echo "usage: validate_record_dmg_layout <absolute-layout-root>" >&2
        return 64
    fi

    local layout_root="$1"
    if [[ "$layout_root" != /* || "$layout_root" == "/" \
          || ! -d "$layout_root" || -L "$layout_root" ]]; then
        echo "DMG layout root is missing or unsafe: $layout_root" >&2
        return 1
    fi
    layout_root="$(cd "$layout_root" && pwd -P)"
    if [[ "$layout_root" == "/" ]]; then
        echo "DMG layout root must be a specific directory" >&2
        return 1
    fi

    local app_path="$layout_root/$RECORD_DMG_APP_NAME"
    if [[ ! -d "$app_path" || -L "$app_path" ]]; then
        echo "DMG app must be a real directory" >&2
        return 1
    fi

    local applications_link="$layout_root/$RECORD_DMG_APPLICATIONS_LINK_NAME"
    if [[ ! -L "$applications_link" ]]; then
        echo "DMG Applications entry must be a symbolic link" >&2
        return 1
    fi
    local applications_target
    applications_target="$(/usr/bin/readlink "$applications_link")"
    if [[ "$applications_target" != "$RECORD_DMG_APPLICATIONS_LINK_TARGET" ]]; then
        echo "DMG Applications link target is invalid: $applications_target" >&2
        return 1
    fi

    local unexpected_entry
    unexpected_entry="$(
        /usr/bin/find "$layout_root" -mindepth 1 -maxdepth 1 \
            ! -name "$RECORD_DMG_APP_NAME" \
            ! -name "$RECORD_DMG_APPLICATIONS_LINK_NAME" \
            -print -quit
    )"
    if [[ -n "$unexpected_entry" ]]; then
        echo "DMG layout contains an unexpected entry: $unexpected_entry" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    validate_record_dmg_layout "$@"
    printf 'validated %s plus %s -> %s\n' \
        "$RECORD_DMG_APP_NAME" \
        "$RECORD_DMG_APPLICATIONS_LINK_NAME" \
        "$RECORD_DMG_APPLICATIONS_LINK_TARGET"
fi
