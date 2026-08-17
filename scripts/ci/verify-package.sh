#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"
artifacts_root="$repo_root/.build/release-artifacts"
dmg_path="$artifacts_root/Record.dmg"

cd "$repo_root"
./scripts/release/package.sh

cd "$artifacts_root"
shasum -a 256 -c SHA256SUMS

if unzip -Z1 Record.zip | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
    echo "Record.zip contains forbidden macOS metadata files" >&2
    exit 1
fi
if grep -q '/Users/' Package.resolved BUILD-METADATA.txt; then
    echo "release metadata contains an absolute user path" >&2
    exit 1
fi

mount_point="$(mktemp -d /tmp/record-dmg.XXXXXX)"
cleanup() {
    /usr/bin/hdiutil detach "$mount_point" -quiet 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

/usr/bin/hdiutil verify "$dmg_path"
/usr/bin/hdiutil attach "$dmg_path" -nobrowse -readonly -noautoopen \
    -mountpoint "$mount_point" -quiet
validate_record_dmg_layout "$mount_point"
mounted_app="$mount_point/$RECORD_DMG_APP_NAME"
"$repo_root/scripts/ci/check-app-bundle.sh" "$mounted_app"
/usr/bin/codesign --verify --deep --strict "$mounted_app"
