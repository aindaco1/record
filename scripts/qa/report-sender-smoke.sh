#!/usr/bin/env bash
set -euo pipefail
if [[ ( $# -ne 1 && $# -ne 3 ) || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.app> [--send-synthetic UUID]" >&2
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
probe_identifier="com.aindaco.record.probe.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
mkdir -p "$probe/Contents/MacOS" "$probe/Contents/XPCServices"
ditto --norsrc --noextattr "$helper" "$probe/Contents/XPCServices/RecordReportSender.xpc"
cat > "$probe/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$probe_identifier</string>
<key>RecordReportSenderServiceName</key><string>$probe_identifier.sender</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc "$repo_root/scripts/qa/report-sender-smoke.swift" -o "$probe/Contents/MacOS/probe"
# Match a locally available signed helper's identity; package-gate helpers are ad hoc.
signing_identity="$(codesign --display --verbose=2 "$helper" 2>&1 | awk -F= '$1 == "Authority" && !found {sub(/^Authority=/, ""); print; found=1}')"
signing_identity="${signing_identity:--}"
# Isolate disposable tests from the user's production sandbox container identity.
probe_helper="$probe/Contents/XPCServices/RecordReportSender.xpc"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $probe_identifier.sender" "$probe_helper/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "$signing_identity" \
    --preserve-metadata=entitlements "$probe_helper"
codesign --force --options runtime --timestamp=none --sign "$signing_identity" \
    --entitlements "$repo_root/Configuration/Record.entitlements" "$probe"
python3 - "$probe/Contents/MacOS/probe" "${@:2}" <<'PYTHON'
import subprocess
import sys
try:
    result = subprocess.run(sys.argv[1:], timeout=45, check=False)
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    sys.exit("Report probe could not finish sandbox startup or XPC within 45 seconds")
PYTHON
