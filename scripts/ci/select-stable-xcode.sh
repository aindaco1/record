#!/usr/bin/env bash
set -euo pipefail

readonly developer_directory="/Applications/Xcode_27.0.app/Contents/Developer"
readonly expected_version="Xcode 27.0"
readonly expected_build="Build version 27A266a"

if [[ ! -d "$developer_directory" ]]; then
    echo "required released toolchain is missing: $developer_directory" >&2
    exit 1
fi

if [[ "$(xcode-select --print-path)" != "$developer_directory" ]]; then
    sudo xcode-select --switch "$developer_directory"
fi

xcode_version="$(xcodebuild -version)"
if [[ "$xcode_version" != "$expected_version"$'\n'"$expected_build" ]]; then
    echo "expected $expected_version ($expected_build), found:" >&2
    printf '%s\n' "$xcode_version" >&2
    exit 1
fi

printf '%s\n' "$xcode_version"
swift --version
