#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/ci/source-contract-gate.sh
git diff --quiet -- .
git diff --cached --quiet -- .
git diff --check
echo "immutable release checkout gate passed"
