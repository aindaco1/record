#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <Record.app> <signing-identity> [timestamp|none]" >&2
    exit 64
fi

app_path="$1"
signing_identity="$2"
timestamp_mode="${3:-none}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
framework="$app_path/Contents/Frameworks/Sparkle.framework"
current="$framework/Versions/Current"

if [[ ! -d "$app_path" || ! -d "$framework" ]]; then
    echo "missing Record app or Sparkle framework" >&2
    exit 1
fi

case "$timestamp_mode" in
    timestamp) timestamp_flag=(--timestamp) ;;
    none) timestamp_flag=(--timestamp=none) ;;
    *) echo "invalid timestamp mode: $timestamp_mode" >&2; exit 64 ;;
esac

# iCloud File Provider may reattach Finder metadata between assembly and
# signing. Strip it at the last possible moment from the exact app bundle.
xattr -cr "$app_path"

common_flags=(
    --force
    --options runtime
    "${timestamp_flag[@]}"
    --sign "$signing_identity"
)

# Sparkle's sandbox services and helper tools must be signed inside-out. Keep
# Downloader's upstream entitlements intact and never use codesign --deep.
codesign "${common_flags[@]}" "$current/XPCServices/Installer.xpc"
codesign "${common_flags[@]}" --preserve-metadata=entitlements \
    "$current/XPCServices/Downloader.xpc"
codesign "${common_flags[@]}" "$current/Autoupdate"
codesign "${common_flags[@]}" "$current/Updater.app"
codesign "${common_flags[@]}" "$framework"
xattr -cr "$app_path"
codesign "${common_flags[@]}" \
    --entitlements "$repo_root/Configuration/Record.entitlements" \
    "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
"$repo_root/scripts/ci/check-signed-entitlements.sh" "$app_path"
