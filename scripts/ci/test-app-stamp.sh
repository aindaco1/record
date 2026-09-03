#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/record-app-stamp.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT
app_path="$test_root/Record.app"
model_downloader="$app_path/Contents/XPCServices/RecordModelDownloader.xpc"
mkdir -p "$app_path/Contents" "$model_downloader/Contents"
cp "$repo_root/Sources/Record/Info.plist" "$app_path/Contents/Info.plist"
cp "$repo_root/Sources/RecordModelDownloaderService/Info.plist" \
    "$model_downloader/Contents/Info.plist"

"$repo_root/scripts/release/stamp-app.sh" "$app_path" 1.2.3 45
test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
    "$app_path/Contents/Info.plist")" = 1.2.3
test "$(/usr/bin/plutil -extract CFBundleVersion raw -o - \
    "$app_path/Contents/Info.plist")" = 45
test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
    "$model_downloader/Contents/Info.plist")" = 1.2.3
test "$(/usr/bin/plutil -extract CFBundleVersion raw -o - \
    "$model_downloader/Contents/Info.plist")" = 45

if "$repo_root/scripts/release/stamp-app.sh" "$app_path" ../bad 45 \
    >/dev/null 2>&1; then
    echo "app stamp accepted an invalid version" >&2
    exit 1
fi
if "$repo_root/scripts/release/stamp-app.sh" "$app_path" 1.2.3 0 \
    >/dev/null 2>&1; then
    echo "app stamp accepted an invalid build number" >&2
    exit 1
fi

echo "app version stamp tests passed"
