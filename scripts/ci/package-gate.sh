#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="$repo_root/.build/release-artifacts/Record.app"

cd "$repo_root"
./scripts/release/build-app.sh

test -x "$app_path/Contents/MacOS/record"
plutil -lint "$app_path/Contents/Info.plist" >/dev/null
architectures="$(lipo -archs "$app_path/Contents/MacOS/record")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only app binary, found: $architectures" >&2
    exit 1
fi

# File Provider can reattach Finder metadata after build-app's cleanup when the
# workspace is in iCloud. Clear it at the last possible moment before signing.
xattr -cr "$app_path"
codesign --force --sign - \
    --entitlements Configuration/Record.entitlements "$app_path"
./scripts/ci/check-signed-entitlements.sh "$app_path"
./scripts/ci/verify-package.sh
