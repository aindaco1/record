#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifacts_root="$repo_root/.build/release-artifacts"
app_path="$artifacts_root/Record.app"
metadata_path="$artifacts_root/BUILD-METADATA.txt"

if [[ ! -d "$app_path" ]]; then
    echo "missing app bundle: $app_path" >&2
    exit 1
fi

source_commit="$(git -C "$repo_root" rev-parse HEAD)"
source_tree="$(git -C "$repo_root" rev-parse 'HEAD^{tree}')"
source_date="$(git -C "$repo_root" show -s --format=%cI HEAD)"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$app_path/Contents/Info.plist")"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$app_path/Contents/Info.plist")"
architectures="$(lipo -archs "$app_path/Contents/MacOS/record")"
swift_output="$(swift --version)"
swift_version="${swift_output%%$'\n'*}"
xcode_version="$(xcodebuild -version | /usr/bin/tr '\n' ';')"

temporary_path="$(mktemp "$artifacts_root/.BUILD-METADATA.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
{
    printf 'SOURCE_COMMIT=%s\n' "$source_commit"
    printf 'SOURCE_TREE=%s\n' "$source_tree"
    printf 'SOURCE_DATE=%s\n' "$source_date"
    printf 'APP_VERSION=%s\n' "$app_version"
    printf 'BUILD_NUMBER=%s\n' "$build_number"
    printf 'MINIMUM_MACOS=%s\n' "$minimum_macos"
    printf 'ARCHITECTURES=%s\n' "$architectures"
    printf 'SWIFT=%s\n' "$swift_version"
    printf 'XCODE=%s\n' "$xcode_version"
} > "$temporary_path"
chmod 0644 "$temporary_path"
mv "$temporary_path" "$metadata_path"
trap - EXIT
