#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <vMAJOR.MINOR.PATCH>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_tag="$1"
version="${release_tag#v}"
artifacts_root="$repo_root/.build/release-artifacts"
archive_path="$artifacts_root/Record.zip"
notes_path="${RECORD_RELEASE_NOTES_PATH:-$repo_root/docs/releases/$version.md}"
appcast_path="$artifacts_root/appcast.xml"
generate_appcast="$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

"$repo_root/scripts/release/validate-tag-format.sh" "$release_tag"

if [[ ! -f "$archive_path" ]]; then
    echo "missing signed update archive: $archive_path" >&2
    exit 1
fi
if [[ ! -f "$notes_path" ]]; then
    echo "missing release notes: $notes_path" >&2
    exit 1
fi
if [[ ! -x "$generate_appcast" ]]; then
    echo "missing Sparkle generate_appcast tool: $generate_appcast" >&2
    exit 1
fi
if [[ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
    echo "SPARKLE_ED25519_PRIVATE_KEY is required" >&2
    exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/record-appcast.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

# Sparkle associates notes with an archive by basename. Keep the release input
# isolated so prior artifacts can never leak into a newly generated feed.
install -m 0644 "$archive_path" "$work_root/Record.zip"
install -m 0644 "$notes_path" "$work_root/Record.md"

printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" | "$generate_appcast" \
    --ed-key-file - \
    --download-url-prefix \
        "https://github.com/aindaco1/record/releases/download/$release_tag/" \
    --embed-release-notes \
    --full-release-notes-url \
        "https://github.com/aindaco1/record/blob/main/CHANGELOG.md" \
    --link "https://github.com/aindaco1/record" \
    --maximum-deltas 0 \
    -o "$work_root/appcast.xml" \
    "$work_root"

for required_fragment in \
    "releases/download/$release_tag/Record.zip" \
    "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" \
    'sparkle:edSignature=' \
    '<!-- sparkle-signatures:'
do
    if ! grep -Fq "$required_fragment" "$work_root/appcast.xml"; then
        echo "generated appcast is missing: $required_fragment" >&2
        exit 1
    fi
done

install -m 0644 "$work_root/appcast.xml" "$appcast_path"
echo "$appcast_path"
