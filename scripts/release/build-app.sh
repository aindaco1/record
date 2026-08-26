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
mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Resources" \
    "$app_path/Contents/Resources/Licenses" \
    "$app_path/Contents/Frameworks"

cd "$repo_root"
swift build -c release --arch arm64 --disable-automatic-resolution
binary_path="$(
    swift build -c release --arch arm64 --disable-automatic-resolution \
        --show-bin-path
)/record"
binary_root="$(dirname "$binary_path")"
sparkle_framework="$binary_root/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
    echo "missing Sparkle framework: $sparkle_framework" >&2
    exit 1
fi
install -m 0755 "$binary_path" "$app_path/Contents/MacOS/record"
ditto --norsrc --noextattr \
    "$sparkle_framework" \
    "$app_path/Contents/Frameworks/Sparkle.framework"
install -m 0644 Sources/Record/Info.plist "$app_path/Contents/Info.plist"
install -m 0644 Sources/Record/Resources/Record.icns \
    "$app_path/Contents/Resources/Record.icns"
install -m 0755 scripts/setup/record-macwhisper-wrapper.sh \
    "$app_path/Contents/Resources/record-macwhisper"
install -m 0644 THIRD_PARTY_NOTICES.md \
    "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
install -m 0644 LICENSE \
    "$app_path/Contents/Resources/Licenses/Record-MIT.txt"
install -m 0644 .build/checkouts/swift-argument-parser/LICENSE.txt \
    "$app_path/Contents/Resources/Licenses/Swift-Argument-Parser-Apache-2.0.txt"
install -m 0644 .build/checkouts/FluidAudio/LICENSE \
    "$app_path/Contents/Resources/Licenses/FluidAudio-Apache-2.0.txt"
install -m 0644 .build/checkouts/Sparkle/LICENSE \
    "$app_path/Contents/Resources/Licenses/Sparkle.txt"

# SwiftPM ad-hoc signs build products in place. That signature is invalid once
# the executable moves into a bundle; the release workflow signs the complete
# app after assembly.
codesign --remove-signature "$app_path/Contents/MacOS/record"

"$repo_root/scripts/release/stamp-app.sh" "$app_path" "$version" "$build_number"

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
