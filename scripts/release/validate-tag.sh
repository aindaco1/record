#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$repo_root/scripts/release/validate-tag-format.sh" "$@"
tag="$1"

git verify-tag "$tag"
tag_commit="$(git rev-parse "$tag^{commit}")"
head_commit="$(git rev-parse HEAD)"
if [[ "$tag_commit" != "$head_commit" ]]; then
    echo "release tag does not identify the checked-out commit" >&2
    exit 1
fi
