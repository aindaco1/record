#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"

fixture_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/record-dmg-layout-test.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

make_fixture() {
    local name="$1"
    local root="$fixture_root/$name"
    /bin/mkdir -p "$root/$RECORD_DMG_APP_NAME"
    /bin/ln -s "$RECORD_DMG_APPLICATIONS_LINK_TARGET" \
        "$root/$RECORD_DMG_APPLICATIONS_LINK_NAME"
    printf '%s\n' "$root"
}

expect_rejection() {
    local root="$1"
    local reason="$2"
    if validate_record_dmg_layout "$root" >/dev/null 2>&1; then
        echo "DMG layout unexpectedly accepted: $reason" >&2
        exit 1
    fi
}

valid="$(make_fixture valid)"
validate_record_dmg_layout "$valid"

missing="$(make_fixture missing-applications)"
/bin/rm "$missing/$RECORD_DMG_APPLICATIONS_LINK_NAME"
expect_rejection "$missing" "missing Applications shortcut"

redirected="$(make_fixture redirected-applications)"
/bin/rm "$redirected/$RECORD_DMG_APPLICATIONS_LINK_NAME"
/bin/ln -s /tmp "$redirected/$RECORD_DMG_APPLICATIONS_LINK_NAME"
expect_rejection "$redirected" "redirected Applications shortcut"

directory="$(make_fixture directory-applications)"
/bin/rm "$directory/$RECORD_DMG_APPLICATIONS_LINK_NAME"
/bin/mkdir "$directory/$RECORD_DMG_APPLICATIONS_LINK_NAME"
expect_rejection "$directory" "Applications directory instead of shortcut"

extra="$(make_fixture extra-entry)"
/usr/bin/touch "$extra/Read Me.txt"
expect_rejection "$extra" "unexpected top-level entry"

linked_app="$(make_fixture linked-app)"
/bin/rmdir "$linked_app/$RECORD_DMG_APP_NAME"
/bin/ln -s /tmp "$linked_app/$RECORD_DMG_APP_NAME"
expect_rejection "$linked_app" "symlinked app bundle"

expect_rejection "relative-layout" "relative layout root"
expect_rejection / "filesystem root"

echo "DMG layout tests passed"
