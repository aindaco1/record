#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/record-action-pinning.XXXXXX")"
cleanup() {
    rm -f "$test_root/workflow.yml" "$test_root/error.log"
    rmdir "$test_root"
}
trap cleanup EXIT

cat > "$test_root/workflow.yml" <<'YAML'
name: Pinned action fixtures
jobs:
  test:
    steps:
      - uses: ./local-action
      - uses: "actions/checkout@1111111111111111111111111111111111111111"
      - uses: docker://example.invalid/tool@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
"$repo_root/scripts/ci/verify-actions-pinning.sh" "$test_root"

cat > "$test_root/workflow.yml" <<'YAML'
name: Unpinned action fixture
jobs:
  test:
    steps:
      - uses: actions/checkout@v4
YAML
if "$repo_root/scripts/ci/verify-actions-pinning.sh" "$test_root" \
    > /dev/null 2> "$test_root/error.log"
then
    echo "action pinning guard accepted an unpinned action" >&2
    exit 1
fi
grep -Fq 'actions/checkout@v4' "$test_root/error.log"

echo "action pinning guard fixtures passed"
