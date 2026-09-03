#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="${1:-$repo_root/Sources/RecordModelDownload}"
service_root="${2:-$repo_root/Sources/RecordModelDownloaderService}"
entitlements="${3:-$repo_root/Configuration/RecordModelDownloader.entitlements}"

if [[ ! -d "$source_root" || ! -d "$service_root" ]]; then
    echo "missing model downloader source roots" >&2
    exit 1
fi

source_files=()
while IFS= read -r -d '' source_file; do
    source_files+=("$source_file")
done < <(
    find "$source_root" "$service_root" -type f -name '*.swift' -print0
)

forbidden_imports='^[[:space:]]*(import|@import)[[:space:]]+(Network|NetworkExtension|WebKit)([;.[:space:]]|$)'
forbidden_calls='(^|[^[:alnum:]_.])(socket|connect|getaddrinfo|gethostbyname|sendto|recvfrom)[[:space:]]*[(]|Darwin[.](socket|connect|getaddrinfo|gethostbyname|sendto|recvfrom)[[:space:]]*[(]'
forbidden_urls='URL[[:space:]]*[(][[:space:]]*string:[[:space:]]*"https?://'
forbidden_tools='/(usr/bin|usr/local/bin|opt/homebrew/bin)/(curl|wget|nc)'

for pattern in \
    "$forbidden_imports" \
    "$forbidden_calls" \
    "$forbidden_urls" \
    "$forbidden_tools"
do
    if grep -EnH "$pattern" "${source_files[@]}"; then
        echo "model downloader boundary violation" >&2
        exit 1
    fi
done

if ! grep -Eq 'URLSession(Configuration|DownloadTask|TaskDelegate)' "${source_files[@]}"; then
    echo "model downloader must use the reviewed Foundation URLSession path" >&2
    exit 1
fi
if grep -Eq 'URLRequest[[:space:]]*[(]' "${source_files[@]}"; then
    echo "model downloader must not accept or construct configurable requests" >&2
    exit 1
fi
if [[ -f "$source_root/ParakeetRemoteDownloader.swift" ]]; then
    if ! grep -Fq 'private let descriptor: ParakeetModelDownloadDescriptor' \
        "$source_root/ParakeetRemoteDownloader.swift" || \
        ! grep -Fq 'descriptor = .v3' \
            "$source_root/ParakeetRemoteDownloader.swift" || \
        ! grep -Fq 'private let downloader = ParakeetRemoteDownloader()' \
            "$service_root/main.swift"; then
        echo "model downloader endpoint must remain private and fixed by the service" >&2
        exit 1
    fi
fi

"$repo_root/scripts/ci/check-model-downloader-entitlements.sh" "$entitlements"
