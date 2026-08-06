#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/ci/check-local-only.sh
./scripts/ci/test-local-only-guard.sh
swift format lint --strict --configuration .swift-format --recursive \
    Package.swift Sources/RecordCore Sources/Record/FluidAudioOfflinePolicy.swift \
    Tests/RecordCoreTests Tests/RecordTests
swift package resolve
git diff --exit-code -- Package.resolved
swift test
swift build -c release --arch arm64

binary_path="$(swift build -c release --arch arm64 --show-bin-path)/record"
architectures="$(lipo -archs "$binary_path")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only binary, found: $architectures" >&2
    exit 1
fi
