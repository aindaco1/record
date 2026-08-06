#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

for sanitizer in thread address; do
    echo "running Swift tests with $sanitizer sanitizer"
    swift test --sanitize="$sanitizer"
done
