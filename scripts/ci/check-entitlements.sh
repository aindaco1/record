#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <entitlements.plist>" >&2
    exit 64
fi

entitlements="$1"
if [[ ! -f "$entitlements" ]]; then
    echo "missing entitlements: $entitlements" >&2
    exit 1
fi

plutil -lint "$entitlements" >/dev/null

required_keys=(
    com.apple.security.app-sandbox
    com.apple.security.device.audio-input
    com.apple.security.files.bookmarks.app-scope
    com.apple.security.files.user-selected.read-write
)

for key in "${required_keys[@]}"; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements")"
    if [[ "$value" != "true" ]]; then
        echo "required entitlement is not true: $key" >&2
        exit 1
    fi
done

for key in \
    com.apple.security.device.camera \
    com.apple.security.network.client \
    com.apple.security.network.server
do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$entitlements" >/dev/null 2>&1; then
        echo "Record must not carry unneeded entitlement: $key" >&2
        exit 1
    fi
done

mach_services="$({
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name' \
        "$entitlements"
} | /usr/bin/awk '/com[.]aindaco[.]record-spk[si]/ { print $1 }')"
expected_mach_services=$'com.aindaco.record-spks\ncom.aindaco.record-spki'
if [[ "$mach_services" != "$expected_mach_services" ]]; then
    echo "unexpected Sparkle mach service exceptions" >&2
    exit 1
fi

if plutil -p "$entitlements" | grep -Eq 'com[.]apple[.]security[.]temporary-exception[.]network'; then
    echo "Record must not carry temporary network exceptions" >&2
    exit 1
fi
