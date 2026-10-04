#!/usr/bin/env python3
"""Compile native catalogs; --check detects incomplete or stale resources."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = {
    ROOT / "Resources/Localizable.xcstrings": ROOT / "Sources/RecordCore/Localization",
    ROOT / "Resources/InfoPlist.xcstrings": ROOT / "Sources/Record/Resources/Localization",
    ROOT / "Resources/AppShortcuts.xcstrings": ROOT / "Sources/Record/Resources/ShortcutLocalization",
}


def placeholders(text):
    return sorted(re.findall(r"%(?:[0-9]+\$)?(?:l[du]|[@dfsu])", text.replace("%%", "")))


def compile_catalog(catalog, output, check):
    data = json.loads(catalog.read_text())
    for key, entry in data["strings"].items():
        english = entry["localizations"]["en"]["stringUnit"]["value"]
        for language in ("en", "es"):
            unit = entry["localizations"][language]["stringUnit"]
            if unit["state"] != "translated" or not unit["value"]:
                raise SystemExit(f"Incomplete {language} translation: {key}")
            if placeholders(english) != placeholders(unit["value"]):
                raise SystemExit(f"Format arguments differ for {language}: {key}")
    with tempfile.TemporaryDirectory(prefix="record-localization-") as temp:
        subprocess.run(["xcrun", "xcstringstool", "compile", str(catalog),
                        "--output-directory", temp], check=True, capture_output=True)
        generated = {p.relative_to(temp): p.read_bytes() for p in Path(temp).rglob("*") if p.is_file()}
        if check:
            existing = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
            if existing != generated:
                raise SystemExit("Localization resources are stale; run scripts/localization/compile.py")
        else:
            for path, content in generated.items():
                destination = output / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
    print(f"Checked {len(data['strings'])} English/Spanish entries in {catalog.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for catalog, output in CATALOGS.items():
        compile_catalog(catalog, output, args.check)
    # Literal lookups must never silently fall back to English in the Spanish UI.
    entries = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
    for source in (ROOT / "Sources").rglob("*.swift"):
        for match in re.finditer(r'L10n\.(?:text|format)\(\s*"((?:[^"\\]|\\.)*)"', source.read_text()):
            key = json.loads('"' + match.group(1) + '"')
            if key not in entries:
                raise SystemExit(f"Missing catalog key in {source.name}: {key}")


if __name__ == "__main__":
    main()
