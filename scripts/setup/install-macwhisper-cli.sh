#!/usr/bin/env bash
set -euo pipefail

source_cli="${1:-/Applications/MacWhisper.app/Contents/MacOS/mw}"
expected_team_id="8Q7TMPA46J"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
wrapper_source="$repo_root/scripts/setup/record-macwhisper-wrapper.sh"
record_user_home="${RECORD_USER_HOME:-}"
if [[ -z "$record_user_home" ]]; then
    record_user_home="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
fi
target_directory="$record_user_home/Library/Application Scripts/com.aindaco.record"
target="$target_directory/record-macwhisper"

if [[ ! -x "$source_cli" ]]; then
    echo "MacWhisper CLI is not executable at $source_cli" >&2
    exit 1
fi
if ! codesign --verify --strict "$source_cli"; then
    echo "MacWhisper CLI signature validation failed" >&2
    exit 1
fi
team_id="$(codesign -dv --verbose=4 "$source_cli" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
if [[ "$team_id" != "$expected_team_id" ]]; then
    echo "unexpected MacWhisper CLI signing team: $team_id" >&2
    exit 1
fi
if [[ ! -x "$wrapper_source" ]]; then
    echo "MacWhisper wrapper is missing or not executable: $wrapper_source" >&2
    exit 1
fi

mkdir -p "$target_directory"
if [[ -e "$target" ]]; then
    if cmp -s "$wrapper_source" "$target"; then
        echo "MacWhisper helper is already installed at $target"
        exit 0
    fi
    echo "refusing to overwrite a different helper at $target" >&2
    echo "move it aside, then rerun this installer" >&2
    exit 1
fi

staging_directory="$(mktemp -d "$target_directory/.record-macwhisper.XXXXXX")"
staged_cli="$staging_directory/record-macwhisper"
cleanup() {
    if [[ -d "${staging_directory:-}" ]]; then
        rm -rf -- "$staging_directory"
    fi
}
trap cleanup EXIT
cp "$wrapper_source" "$staged_cli"
chmod 0755 "$staged_cli"
mv "$staged_cli" "$target"

echo "Installed MacWhisper user-script helper at $target"
echo "The helper validates signing team $expected_team_id before every launch."
