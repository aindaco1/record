#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <Developer-ID-signed Record.app>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
identity="$repo_root/Configuration/TCCIdentity.plist"
app_path="$1"

if [[ ! -d "$app_path" ]]; then
    echo "missing app bundle: $app_path" >&2
    exit 1
fi

expected_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :BundleIdentifier' "$identity")"
expected_team_id="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier' "$identity")"
actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app_path/Contents/Info.plist")"

if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "TCC identity changed: expected bundle $expected_bundle_id, found $actual_bundle_id" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
signature="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
team_id="$(printf '%s\n' "$signature" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ "$team_id" != "$expected_team_id" ]]; then
    echo "TCC identity changed: expected team $expected_team_id, found ${team_id:-none}" >&2
    exit 1
fi
if ! printf '%s\n' "$signature" | grep -Eq '^CodeDirectory .*\(runtime\)'; then
    echo "release app is missing the hardened runtime" >&2
    exit 1
fi

requirement="$(codesign -dr - "$app_path" 2>&1)"
for fragment in \
    "identifier \"$expected_bundle_id\"" \
    'anchor apple generic' \
    'certificate 1[field.1.2.840.113635.100.6.2.6]' \
    'certificate leaf[field.1.2.840.113635.100.6.1.13]' \
    "certificate leaf[subject.OU] = $expected_team_id"
do
    if [[ "$requirement" != *"$fragment"* ]]; then
        echo "release designated requirement is missing: $fragment" >&2
        echo "$requirement" >&2
        exit 1
    fi
done

echo "stable TCC identity verified: $expected_bundle_id / $expected_team_id"
