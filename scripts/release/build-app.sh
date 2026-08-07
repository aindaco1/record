#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifacts_root="$repo_root/.build/release-artifacts"
app_path="$artifacts_root/Record.app"
version="${RECORD_VERSION:-0.0.0-dev}"
build_number="${RECORD_BUILD_NUMBER:-1}"

case "$artifacts_root" in
    "$repo_root"/.build/*) ;;
    *) echo "refusing unsafe artifact path: $artifacts_root" >&2; exit 1 ;;
esac

rm -rf "$artifacts_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

cd "$repo_root"
swift build -c release --arch arm64
binary_path="$(swift build -c release --arch arm64 --show-bin-path)/record"
install -m 0755 "$binary_path" "$app_path/Contents/MacOS/record"
install -m 0644 Sources/Record/Info.plist "$app_path/Contents/Info.plist"
install -m 0644 Sources/Record/Resources/Record.icns \
    "$app_path/Contents/Resources/Record.icns"
install -m 0644 THIRD_PARTY_NOTICES.md \
    "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"

# SwiftPM ad-hoc signs build products in place. That signature is invalid once
# the executable moves into a bundle; the release workflow signs the complete
# app after assembly.
codesign --remove-signature "$app_path/Contents/MacOS/record"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
    "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" \
    "$app_path/Contents/Info.plist"

# Cloud-synced workspaces can attach Finder/resource-fork metadata that makes
# an otherwise valid bundle fail strict code-sign verification.
xattr -cr "$app_path"

architectures="$(lipo -archs "$app_path/Contents/MacOS/record")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only binary, found: $architectures" >&2
    exit 1
fi

plutil -lint "$app_path/Contents/Info.plist"
if codesign --verify "$app_path" >/dev/null 2>&1; then
    echo "expected unsigned app before the release signing step" >&2
    exit 1
fi
echo "$app_path"
