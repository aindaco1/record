#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$repo_root/scripts/ci/check-local-only.sh"
entitlements="$repo_root/Configuration/Record.entitlements"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/record-local-only.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

safe="$temporary_root/safe"
mkdir -p "$safe"
printf '%s\n' 'import Foundation' 'let value = "local"' > "$safe/Safe.swift"
"$guard" "$safe" "$entitlements"

assert_rejected() {
    local name="$1"
    local source="$2"
    local fixture="$temporary_root/$name"
    mkdir -p "$fixture"
    printf '%s\n' "$source" > "$fixture/Fixture.swift"
    if "$guard" "$fixture" "$entitlements" >/dev/null 2>&1; then
        echo "local-only guard accepted forbidden fixture: $name" >&2
        exit 1
    fi
}

assert_rejected network-import 'import Network'
assert_rejected url-session 'let session = URLSession.shared'
assert_rejected raw-socket 'let descriptor = socket(AF_INET, SOCK_STREAM, 0)'
assert_rejected remote-url 'let endpoint = URL(string: "https://example.invalid")'
assert_rejected external-tool 'let executable = "/usr/bin/curl"'

networked_entitlements="$temporary_root/networked.entitlements"
cp "$entitlements" "$networked_entitlements"
/usr/libexec/PlistBuddy \
    -c 'Add :com.apple.security.network.client bool true' \
    "$networked_entitlements"
if "$guard" "$safe" "$networked_entitlements" >/dev/null 2>&1; then
    echo "local-only guard accepted a network-client entitlement" >&2
    exit 1
fi
