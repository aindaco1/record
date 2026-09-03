#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="${1:-$repo_root/Sources}"
entitlements="${2:-$repo_root/Configuration/Record.entitlements}"

if [[ ! -d "$source_root" ]]; then
    echo "missing source root: $source_root" >&2
    exit 1
fi

source_files=()
while IFS= read -r -d '' source_file; do
    source_files+=("$source_file")
done < <(
    find "$source_root" -type f \( \
        -name '*.swift' -o \
        -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o \
        -name '*.h' -o -name '*.hpp' -o -name '*.m' -o -name '*.mm' \
    \) \
        ! -path "$source_root/RecordModelDownload/*" \
        ! -path "$source_root/RecordModelDownloaderService/*" \
        -print0
)

forbidden_imports='^[[:space:]]*(import|@import)[[:space:]]+(CFNetwork|FoundationNetworking|Network|NetworkExtension|WebKit)([;.[:space:]]|$)'
forbidden_symbols='URLSession|NSURLSession|NW(Connection|Listener|Browser|PathMonitor)|CF(Read|Write)Stream|CFSocket|GCDAsyncSocket|ClientBootstrap|ServerBootstrap|SentrySDK|PostHogSDK|FirebaseAnalytics'
forbidden_calls='(^|[^[:alnum:]_.])(socket|connect|getaddrinfo|gethostbyname|sendto|recvfrom)[[:space:]]*[(]|Darwin[.](socket|connect|getaddrinfo|gethostbyname|sendto|recvfrom)[[:space:]]*[(]'
forbidden_urls='URL[[:space:]]*[(][[:space:]]*string:[[:space:]]*"https?://'
forbidden_tools='/(usr/bin|usr/local/bin|opt/homebrew/bin)/(curl|wget|nc)'

failed=0
for pattern in \
    "$forbidden_imports" \
    "$forbidden_symbols" \
    "$forbidden_calls" \
    "$forbidden_urls" \
    "$forbidden_tools"
do
    if [[ "${#source_files[@]}" -eq 0 ]]; then
        break
    fi

    set +e
    matches="$(grep -EnH "$pattern" "${source_files[@]}")"
    search_status=$?
    set -e
    if [[ "$search_status" -eq 0 ]]; then
        echo "local-only boundary violation:" >&2
        echo "$matches" >&2
        failed=1
    elif [[ "$search_status" -ne 1 ]]; then
        echo "local-only source scan failed with status $search_status" >&2
        exit "$search_status"
    fi
done

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

"$repo_root/scripts/ci/check-entitlements.sh" "$entitlements"
if [[ -d "$source_root/RecordModelDownload" && \
      -d "$source_root/RecordModelDownloaderService" ]]; then
    "$repo_root/scripts/ci/check-model-downloader-source.sh" \
        "$source_root/RecordModelDownload" \
        "$source_root/RecordModelDownloaderService"
fi
