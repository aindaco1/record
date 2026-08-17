#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.dmg>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"
dmg_path="$1"

if [[ "${dmg_path##*/}" != "Record.dmg" || ! -f "$dmg_path" \
      || -L "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "DMG artifact is missing or unsafe: $dmg_path" >&2
    exit 1
fi

/usr/bin/hdiutil verify "$dmg_path"
/usr/bin/codesign --verify --strict --verbose=2 "$dmg_path"
/usr/bin/xcrun stapler validate "$dmg_path"
/usr/sbin/spctl --assess --type open \
    --context context:primary-signature --verbose=2 "$dmg_path"

work_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/record-dmg-verify.XXXXXX")"
mount_point="$work_root/mount"
/bin/mkdir "$mount_point"
attach_attempted=false

cleanup() {
    local status=$?
    trap - EXIT
    set +e
    if [[ "$attach_attempted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$mount_point" -quiet 2>/dev/null; then
            if ! /usr/bin/hdiutil detach "$mount_point" -force -quiet 2>/dev/null; then
                echo "failed to detach verified DMG: $mount_point" >&2
                status=1
            fi
        fi
    fi
    if ! /bin/rm -rf -- "$work_root"; then
        echo "failed to remove private DMG verification directory: $work_root" >&2
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT

attach_attempted=true
/usr/bin/hdiutil attach "$dmg_path" -readonly -nobrowse -noautoopen \
    -mountpoint "$mount_point" -quiet

validate_record_dmg_layout "$mount_point"
mounted_app="$mount_point/$RECORD_DMG_APP_NAME"
"$repo_root/scripts/ci/check-app-bundle.sh" "$mounted_app"
"$repo_root/scripts/ci/check-signed-entitlements.sh" "$mounted_app"
"$repo_root/scripts/ci/check-tcc-identity.sh" "$mounted_app"
/usr/bin/xcrun stapler validate "$mounted_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$mounted_app"

echo "verified signed, notarized Record DMG: $dmg_path"
