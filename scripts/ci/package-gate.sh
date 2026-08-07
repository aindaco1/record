#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="$repo_root/.build/release-artifacts/Record.app"

cd "$repo_root"
./scripts/release/build-app.sh

test -x "$app_path/Contents/MacOS/record"
test -f "$app_path/Contents/Resources/Record.icns"
test -f "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
plutil -lint "$app_path/Contents/Info.plist" >/dev/null
assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist")"
    if [[ "$actual" != "$expected" ]]; then
        echo "expected $key=$expected, found: $actual" >&2
        exit 1
    fi
}

assert_plist_value CFBundleDisplayName Record
assert_plist_value CFBundleIconFile Record.icns
assert_plist_value CFBundleIdentifier com.aindaco.record
assert_plist_value CFBundlePackageType APPL
assert_plist_value NSPrincipalClass NSApplication
assert_plist_value NSUserNotificationAlertStyle alert

if [[ "$(plutil -extract LSUIElement raw -o - "$app_path/Contents/Info.plist")" != "true" ]]; then
    echo "expected LSUIElement=true" >&2
    exit 1
fi
architectures="$(lipo -archs "$app_path/Contents/MacOS/record")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only app binary, found: $architectures" >&2
    exit 1
fi

# File Provider can reattach Finder metadata after build-app's cleanup when the
# workspace is in iCloud. Clear it at the last possible moment before signing.
xattr -cr "$app_path"
codesign --force --sign - \
    --entitlements Configuration/Record.entitlements "$app_path"
./scripts/ci/check-signed-entitlements.sh "$app_path"
./scripts/ci/verify-package.sh
