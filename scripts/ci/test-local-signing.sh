#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/local-signing.sh"

fail() {
    echo "local signing selection test failed: $1" >&2
    exit 1
}

identities='  1) DEVELOPERID "Developer ID Application: Example (TEAMID)"
  2) DEVELOPMENT "Apple Development: Developer (TEAMID)"
     2 valid identities found'

selected="$(select_local_codesign_identity "" "$identities")"
[[ "$selected" == "DEVELOPERID" ]] \
    || fail "expected Developer ID to be preferred, found: $selected"

development_only='  1) DEVELOPMENT "Apple Development: Developer (TEAMID)"
     1 valid identities found'
selected="$(select_local_codesign_identity "" "$development_only")"
[[ "$selected" == "DEVELOPMENT" ]] \
    || fail "expected Apple Development fallback, found: $selected"

selected="$(select_local_codesign_identity "Explicit Identity" "$identities")"
[[ "$selected" == "Explicit Identity" ]] \
    || fail "expected explicit override, found: $selected"

selected="$(select_local_codesign_identity "" "0 valid identities found")"
[[ -z "$selected" ]] || fail "expected no selection, found: $selected"

echo "local signing selection tests passed"
