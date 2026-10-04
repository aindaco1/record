#!/usr/bin/env python3
"""Require the five local recording actions and their packaged translations."""
import json
from pathlib import Path
import subprocess
import sys

resources = Path(sys.argv[1]) / "Contents/Resources"
metadata = json.loads((resources / "Metadata.appintents/extract.actionsdata").read_text())
expected = {"StartRecordingIntent", "StopRecordingIntent", "PauseRecordingIntent",
            "ResumeRecordingIntent", "RecordingStatusIntent"}
assert set(metadata["actions"]) == expected, "Missing or unexpected recording actions"
assert len(metadata["autoShortcuts"]) == 5, "Missing App Shortcuts"
for action in metadata["actions"].values():
    assert action["openAppWhenRun"], "Recording actions must use the running app"
mode = next(item for item in metadata["enums"] if item["identifier"] == "RecordingIntentMode")
assert {item["identifier"] for item in mode["cases"]} == {"screen", "audio", "dictation"}
for language in ("en", "es"):
    for catalog in ("Localizable", "AppShortcuts"):
        path = resources / f"{language}.lproj/{catalog}.strings"
        result = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)])
        strings = json.loads(result)
        if catalog == "Localizable":
            for title in ("Start Recording", "Stop Recording", "Pause Recording",
                          "Resume Recording", "Recording Status", "Quick Dictation"):
                assert strings.get(title), f"Missing {language} action: {title}"
        else:
            assert len(strings) == 5 and all("${applicationName}" in value for value in strings.values())
print("App Intents metadata and English/Spanish resources verified")
