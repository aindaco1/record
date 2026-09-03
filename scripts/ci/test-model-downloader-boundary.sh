#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$repo_root/scripts/ci/check-model-downloader-source.sh"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/record-model-downloader-boundary.XXXXXX")"
cleanup() {
    case "$temporary_root" in
        "${TMPDIR:-/tmp}"/record-model-downloader-boundary.*)
            /bin/rm -rf -- "$temporary_root"
            ;;
        *)
            echo "refusing unsafe fixture cleanup: $temporary_root" >&2
            ;;
    esac
}
trap cleanup EXIT

safe="$temporary_root/safe"
service="$temporary_root/service"
mkdir -p "$safe" "$service"
printf '%s\n' \
    'import Foundation' \
    'let configuration = URLSessionConfiguration.ephemeral' \
    > "$safe/Downloader.swift"
printf '%s\n' 'import Foundation' > "$service/main.swift"
"$guard" "$safe" "$service" \
    "$repo_root/Configuration/RecordModelDownloader.entitlements"

assert_rejected() {
    local name="$1"
    local source="$2"
    local fixture="$temporary_root/$name"
    mkdir -p "$fixture/download" "$fixture/service"
    printf '%s\n' "$source" > "$fixture/download/Downloader.swift"
    printf '%s\n' 'import Foundation' > "$fixture/service/main.swift"
    if "$guard" "$fixture/download" "$fixture/service" \
        "$repo_root/Configuration/RecordModelDownloader.entitlements" \
        >/dev/null 2>&1; then
        echo "model downloader guard accepted forbidden fixture: $name" >&2
        exit 1
    fi
}

assert_rejected arbitrary-url \
    'import Foundation; let url = URL(string: "https://example.invalid/model")!; let configuration = URLSessionConfiguration.ephemeral'
assert_rejected raw-socket \
    'import Foundation; let descriptor = socket(AF_INET, SOCK_STREAM, 0); let configuration = URLSessionConfiguration.ephemeral'
assert_rejected external-tool \
    'import Foundation; let tool = "/usr/bin/curl"; let configuration = URLSessionConfiguration.ephemeral'

expanded_entitlements="$temporary_root/expanded.entitlements"
cp "$repo_root/Configuration/RecordModelDownloader.entitlements" "$expanded_entitlements"
/usr/libexec/PlistBuddy \
    -c 'Add :com.apple.security.files.user-selected.read-write bool true' \
    "$expanded_entitlements"
if "$guard" "$safe" "$service" "$expanded_entitlements" >/dev/null 2>&1; then
    echo "model downloader guard accepted expanded file access" >&2
    exit 1
fi

echo "model downloader boundary tests passed"
