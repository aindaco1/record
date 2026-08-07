#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <recording-session-directory>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
swift build --product record
binary_path="$(swift build --show-bin-path)/record"
exec "$binary_path" inspect-session "$1"
