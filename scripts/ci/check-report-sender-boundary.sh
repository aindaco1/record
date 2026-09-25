#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$repo_root/scripts/ci/check-report-sender-boundary.py" "${1:-$repo_root}"
"$repo_root/scripts/ci/check-model-downloader-entitlements.sh" \
    "$repo_root/Configuration/RecordReportSender.entitlements"
