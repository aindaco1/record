#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.app> <version> <build-number>" >&2
    exit 64
fi
app_path="$1"
version="$2"
build_number="$3"
info_plist="$app_path/Contents/Info.plist"
model_downloader_info="$app_path/Contents/XPCServices/RecordModelDownloader.xpc/Contents/Info.plist"

if [[ ! -d "$app_path" || -L "$app_path" || ! -f "$info_plist" || \
      -L "$info_plist" || \
      ! -f "$model_downloader_info" || -L "$model_downloader_info" || \
      ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$ || \
      ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid Record app version stamp" >&2
    exit 64
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info_plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $version" "$model_downloader_info"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$model_downloader_info"
/usr/bin/plutil -lint "$info_plist" >/dev/null
/usr/bin/plutil -lint "$model_downloader_info" >/dev/null

actual_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
actual_build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist")"
model_downloader_version="$(
    /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$model_downloader_info"
)"
model_downloader_build="$(
    /usr/bin/plutil -extract CFBundleVersion raw -o - "$model_downloader_info"
)"
if [[ "$actual_version" != "$version" || "$actual_build" != "$build_number" ]]; then
    echo "Record app version stamp did not persist" >&2
    exit 1
fi
if [[ "$model_downloader_version" != "$version" || \
      "$model_downloader_build" != "$build_number" ]]; then
    echo "Record model downloader version stamp did not persist" >&2
    exit 1
fi
