#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="${1:-$repo_root/Sources}"
entitlements="${2:-$repo_root/Configuration/Record.entitlements}"

if [[ ! -d "$source_root" ]]; then
    echo "missing source root: $source_root" >&2
    exit 1
fi

source_globs=(
    --glob '*.swift'
    --glob '*.{c,cc,cpp,h,hpp,m,mm}'
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
    set +e
    matches="$(rg --line-number --with-filename "${source_globs[@]}" "$pattern" "$source_root")"
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
