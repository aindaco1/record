#!/usr/bin/env bash
set -euo pipefail

readonly developer_directory="/Applications/Xcode_26.3.app/Contents/Developer"
readonly expected_version="Xcode 26.3"

if [[ ! -d "$developer_directory" ]]; then
    echo "required stable toolchain is missing: $developer_directory" >&2
    exit 1
fi

if [[ "$(xcode-select --print-path)" != "$developer_directory" ]]; then
    sudo xcode-select --switch "$developer_directory"
fi

xcode_version="$(xcodebuild -version)"
if [[ "${xcode_version%%$'\n'*}" != "$expected_version" ]]; then
    echo "expected $expected_version, found:" >&2
    printf '%s\n' "$xcode_version" >&2
    exit 1
fi

printf '%s\n' "$xcode_version"
swift --version
