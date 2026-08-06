#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/ci/preflight.sh
git diff --check
./scripts/ci/container-lint.sh
./scripts/ci/validate.sh
RECORD_VERSION="${RECORD_VERSION:-0.0.0-local}" \
    RECORD_BUILD_NUMBER="${RECORD_BUILD_NUMBER:-1}" \
    ./scripts/ci/package-gate.sh
git diff --check

echo "complete local gate passed for $(git rev-parse --short=12 HEAD)"
