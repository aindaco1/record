#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifacts_root="$repo_root/.build/release-artifacts"

cd "$repo_root"
./scripts/release/package.sh

cd "$artifacts_root"
shasum -a 256 -c SHA256SUMS

if unzip -Z1 Record.zip | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
    echo "Record.zip contains forbidden macOS metadata files" >&2
    exit 1
fi
if grep -q '/Users/' Package.resolved BUILD-METADATA.txt; then
    echo "release metadata contains an absolute user path" >&2
    exit 1
fi

mount_point="$(mktemp -d /tmp/record-dmg.XXXXXX)"
cleanup() {
    hdiutil detach "$mount_point" -quiet 2>/dev/null || true
    rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach Record.dmg -nobrowse -readonly -mountpoint "$mount_point" -quiet
test -d "$mount_point/Record.app"
test -x "$mount_point/Record.app/Contents/MacOS/record"
