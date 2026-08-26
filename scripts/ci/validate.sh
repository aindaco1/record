#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

swift_build_system="${RECORD_SWIFT_BUILD_SYSTEM:-native}"
case "$swift_build_system" in
    native | swiftbuild)
        swift_build_arguments=(--build-system "$swift_build_system")
        ;;
    *)
        echo "unsupported Swift build system: $swift_build_system" >&2
        exit 1
        ;;
esac

./scripts/ci/source-contract-gate.sh
resolved_before="$(shasum -a 256 Package.resolved | awk '{print $1}')"
swift package resolve
resolved_after="$(shasum -a 256 Package.resolved | awk '{print $1}')"
if [[ "$resolved_before" != "$resolved_after" ]]; then
    echo "swift package resolve changed Package.resolved" >&2
    git diff -- Package.resolved >&2
    exit 1
fi
swift test "${swift_build_arguments[@]}"
swift build "${swift_build_arguments[@]}" -c release --arch arm64

binary_path="$(
    swift build "${swift_build_arguments[@]}" -c release --arch arm64 --show-bin-path
)/record"
architectures="$(lipo -archs "$binary_path")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only binary, found: $architectures" >&2
    exit 1
fi
