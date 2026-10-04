#!/usr/bin/env python3
"""Extract App Intents from the exact Swift Build release compilation."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1])
objects = ROOT / ".build/out/Intermediates.noindex/Record.build/Release/record-p.build/Objects-normal/arm64"
constants = objects / "record-primary.swiftconstvalues"
if not constants.is_file():
    raise SystemExit("Missing release App Intents compiler metadata")


def output(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


with tempfile.TemporaryDirectory(prefix="record-app-intents-") as temporary:
    temp = Path(temporary)
    (temp / "sources").write_text(str(ROOT / "Sources/Record/Automation/RecordingAppIntents.swift") + "\n")
    (temp / "constants").write_text(str(constants) + "\n")
    subprocess.run([
        "xcrun", "appintentsmetadataprocessor",
        "--output", str(app / "Contents/Resources"),
        "--toolchain-dir", str(Path(output("xcrun", "--find", "swift")).parents[2]),
        "--module-name", "Record", "--sdk-root", output("xcrun", "--show-sdk-path"),
        "--xcode-version", output("xcodebuild", "-version").split()[-1],
        "--platform-family", "macOS", "--deployment-target", "15.0",
        "--target-triple", "arm64-apple-macosx15.0",
        "--source-file-list", str(temp / "sources"),
        "--swift-const-vals-list", str(temp / "constants"),
    ], check=True)
