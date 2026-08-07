#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "the complete Record gate requires macOS" >&2
    exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "the complete local gate requires Apple Silicon" >&2
    exit 1
fi

required_commands=(
    codesign
    ditto
    git
    hdiutil
    lipo
    plutil
    podman
    rg
    shasum
    swift
    xcodebuild
    xcrun
)
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing required command: $command_name" >&2
        exit 1
    fi
done

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
swift_version="$(swift --version)"
swift_first_line="${swift_version%%$'\n'*}"
xcode_first_line="$(xcodebuild -version | /usr/bin/awk 'NR == 1 { print $0 }')"
xcode_number="${xcode_first_line#Xcode }"
xcode_major="${xcode_number%%.*}"

if [[ ! "$macos_major" =~ ^[0-9]+$ || "$macos_major" -lt 15 ]]; then
    echo "Record requires macOS 15 or newer; found $macos_version" >&2
    exit 1
fi
if [[ ! "$swift_first_line" =~ Swift[[:space:]]version[[:space:]]([0-9]+) ]] \
    || [[ "${BASH_REMATCH[1]}" -lt 6 ]]
then
    echo "Record requires Swift 6 or newer; found $swift_first_line" >&2
    exit 1
fi
if [[ ! "$xcode_major" =~ ^[0-9]+$ || "$xcode_major" -lt 16 ]]; then
    echo "Record requires Xcode 16 or newer; found $xcode_first_line" >&2
    exit 1
fi

xcrun --sdk macosx --show-sdk-path >/dev/null
podman info >/dev/null

echo "local gate environment: macOS $macos_version; $xcode_first_line; $swift_first_line"
