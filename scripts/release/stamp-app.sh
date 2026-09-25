#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.app> <version> <build-number>" >&2
    exit 64
fi
app_path="$1"
version="$2"
build_number="$3"
if [[ ! -d "$app_path" || -L "$app_path" || \
      ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$ || \
      ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid Record app version stamp" >&2
    exit 64
fi
infos=(
    "$app_path/Contents/Info.plist"
    "$app_path/Contents/XPCServices/RecordModelDownloader.xpc/Contents/Info.plist"
    "$app_path/Contents/XPCServices/RecordReportSender.xpc/Contents/Info.plist"
)
# Validate every destination before changing any stamp.
for info in "${infos[@]}"; do
    if [[ ! -f "$info" || -L "$info" ]]; then
        echo "missing or unsafe Record version stamp destination" >&2
        exit 64
    fi
done
for info in "${infos[@]}"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info"
    /usr/bin/plutil -lint "$info" >/dev/null
    if [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info")" != "$version" || \
          "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info")" != "$build_number" ]]; then
        echo "Record version stamp did not persist" >&2
        exit 1
    fi
done
