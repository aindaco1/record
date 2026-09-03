#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <model-downloader-entitlements.plist>" >&2
    exit 64
fi

entitlements="$1"
if [[ ! -f "$entitlements" ]]; then
    echo "missing model downloader entitlements: $entitlements" >&2
    exit 1
fi

/usr/bin/plutil -lint "$entitlements" >/dev/null
for key in com.apple.security.app-sandbox com.apple.security.network.client; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements")"
    if [[ "$value" != "true" ]]; then
        echo "required model downloader entitlement is not true: $key" >&2
        exit 1
    fi
done

key_count="$(/usr/bin/plutil -p "$entitlements" | /usr/bin/grep -c '=>')"
if [[ "$key_count" -ne 2 ]]; then
    echo "model downloader entitlements must contain exactly sandbox and network client" >&2
    exit 1
fi
