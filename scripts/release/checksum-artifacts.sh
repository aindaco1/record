#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifacts_root="$repo_root/.build/release-artifacts"
required_artifacts=(
    Record.zip
    Record.dmg
    Package.resolved
    BUILD-METADATA.txt
)

for artifact in "${required_artifacts[@]}"; do
    if [[ ! -f "$artifacts_root/$artifact" ]]; then
        echo "missing release artifact: $artifact" >&2
        exit 1
    fi
done

cd "$artifacts_root"
shasum -a 256 "${required_artifacts[@]}" > SHA256SUMS
