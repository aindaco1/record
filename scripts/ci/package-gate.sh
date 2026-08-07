#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="$repo_root/.build/release-artifacts/Record.app"

cd "$repo_root"
./scripts/release/build-app.sh

test -x "$app_path/Contents/MacOS/record"
test -d "$app_path/Contents/Frameworks/Sparkle.framework"
test -f "$app_path/Contents/Resources/Record.icns"
test -x "$app_path/Contents/Resources/record-macwhisper"
test -f "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f "$app_path/Contents/Resources/Licenses/Record-MIT.txt"
test -f "$app_path/Contents/Resources/Licenses/Swift-Argument-Parser-Apache-2.0.txt"
test -f "$app_path/Contents/Resources/Licenses/FluidAudio-Apache-2.0.txt"
test -f "$app_path/Contents/Resources/Licenses/Sparkle.txt"
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
assert_plist_value SUFeedURL \
    https://github.com/aindaco1/record/releases/latest/download/appcast.xml
assert_plist_value SUPublicEDKey SmB+aHRo7wfeJAr21p/IlXiDylp6ObIt/uorKzAZfFU=

if plutil -extract NSCameraUsageDescription raw -o - \
    "$app_path/Contents/Info.plist" >/dev/null 2>&1
then
    echo "Record 1.0 must not declare unused camera access" >&2
    exit 1
fi

for key in \
    SUEnableDownloaderService \
    SUEnableInstallerLauncherService \
    SURequireSignedFeed \
    SUVerifyUpdateBeforeExtraction
do
    if [[ "$(plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist")" != "true" ]]; then
        echo "expected $key=true" >&2
        exit 1
    fi
done

for key in SUAllowsAutomaticUpdates SUEnableAutomaticChecks; do
    if [[ "$(plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist")" != "false" ]]; then
        echo "expected $key=false" >&2
        exit 1
    fi
done

if [[ "$(plutil -extract LSUIElement raw -o - "$app_path/Contents/Info.plist")" != "true" ]]; then
    echo "expected LSUIElement=true" >&2
    exit 1
fi
architectures="$(lipo -archs "$app_path/Contents/MacOS/record")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only app binary, found: $architectures" >&2
    exit 1
fi

# Sign and package outside the iCloud-backed workspace. File Provider may
# reattach Finder metadata immediately inside the checkout, even after xattr
# cleanup, while a temporary local bundle remains stable and verifiable.
signing_root="$(mktemp -d "${TMPDIR:-/tmp}/record-package-gate.XXXXXX")"
trap 'rm -rf "$signing_root"' EXIT
signing_app="$signing_root/Record.app"
ditto --norsrc --noextattr "$app_path" "$signing_app"
./scripts/release/sign-app.sh "$signing_app" - none
RECORD_APP_PATH="$signing_app" ./scripts/ci/verify-package.sh

# Exercise the complete signed-feed generator with a disposable matching key
# pair. The production private key exists only in the protected release
# environment, and Sparkle correctly refuses to sign an archive whose embedded
# public key does not match.
test_update_key_path="$signing_root/update-key.pem"
openssl genpkey -algorithm ED25519 -out "$test_update_key_path" 2>/dev/null
test_update_key="$({
    openssl pkey -in "$test_update_key_path" -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
test_update_public_key="$({
    openssl pkey -in "$test_update_key_path" -pubout -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
/usr/libexec/PlistBuddy \
    -c "Set :SUPublicEDKey $test_update_public_key" \
    "$signing_app/Contents/Info.plist"
./scripts/release/sign-app.sh "$signing_app" - none
RECORD_APP_PATH="$signing_app" ./scripts/release/package.sh >/dev/null
SPARKLE_ED25519_PRIVATE_KEY="$test_update_key" \
    RECORD_RELEASE_NOTES_PATH="$repo_root/docs/releases/1.0.0.md" \
    ./scripts/release/generate-appcast.sh "v${RECORD_VERSION:-0.0.0-dev}"
unset test_update_key test_update_public_key
./scripts/release/checksum-artifacts.sh
(cd .build/release-artifacts && shasum -a 256 -c SHA256SUMS)
