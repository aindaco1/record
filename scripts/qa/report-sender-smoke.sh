#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.app>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$1/Contents/XPCServices/RecordReportSender.xpc"
if [[ ! -d "$helper" || -L "$helper" ]]; then
    echo "missing or unsafe report sender" >&2
    exit 1
fi
probe_root="$(mktemp -d "${TMPDIR:-/tmp}/record-report-probe.XXXXXX")"
trap 'rm -rf "$probe_root"' EXIT
probe="$probe_root/RecordReportProbe.app"
mkdir -p "$probe/Contents/MacOS" "$probe/Contents/XPCServices"
ditto --norsrc --noextattr "$helper" "$probe/Contents/XPCServices/RecordReportSender.xpc"
cat > "$probe/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.aindaco.record.report-probe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc "$repo_root/scripts/qa/report-sender-smoke.swift" -o "$probe/Contents/MacOS/probe"
codesign --force --sign - --entitlements "$repo_root/Configuration/Record.entitlements" "$probe"
"$probe/Contents/MacOS/probe"
