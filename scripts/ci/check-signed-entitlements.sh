#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <Record.app>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="$1"
if [[ ! -d "$app_path" ]]; then
    echo "missing app bundle: $app_path" >&2
    exit 1
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/record-entitlements.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
embedded="$temporary_root/embedded.plist"
model_downloader_embedded="$temporary_root/model-downloader.plist"
verification_app="$temporary_root/Record.app"

# File Provider can immediately reapply Finder metadata inside an iCloud-backed
# workspace. Verify an attribute-free byte-for-byte bundle copy so strict
# signing checks measure the artifact contents rather than sync metadata.
ditto --norsrc --noextattr "$app_path" "$verification_app"
codesign --verify --deep --strict "$verification_app"
codesign --display --entitlements "$embedded" --xml "$verification_app"
"$repo_root/scripts/ci/check-entitlements.sh" "$embedded"
model_downloader="$verification_app/Contents/XPCServices/RecordModelDownloader.xpc"
codesign --display --entitlements "$model_downloader_embedded" --xml \
    "$model_downloader"
"$repo_root/scripts/ci/check-model-downloader-entitlements.sh" \
    "$model_downloader_embedded"
