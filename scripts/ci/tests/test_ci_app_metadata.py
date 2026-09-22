"""Exercise the actual release metadata filter with trusted and altered evidence."""

import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[3]
FILTER = ROOT / "scripts/release/ci-app-metadata.jq"


class CIAppMetadataTests(unittest.TestCase):
    def setUp(self):
        self.metadata = {
            "schema": "record-ci-app-v3",
            "repository": "aindaco1/record",
            "commit": "a" * 40,
            "workflow": ".github/workflows/ci.yml",
            "runID": 42,
            "runAttempt": 2,
            "runner": "github-hosted",
            "xcodeVersion": "Xcode 27.0",
            "xcodeBuild": "27A266a",
            "appVersion": "0.0.0-ci",
            "buildNumber": "21",
        }
        for key in (
            "packageResolvedSHA256", "buildAppSHA256", "stampAppSHA256",
            "bundleCheckSHA256", "sourceInfoPlistSHA256", "executableSHA256",
            "modelDownloaderInfoPlistSHA256", "modelDownloaderExecutableSHA256",
        ):
            self.metadata[key] = "b" * 64

    def accepts(self, metadata):
        result = subprocess.run(
            ["jq", "-e", "--arg", "repository", "aindaco1/record",
             "--arg", "commit", "a" * 40, "--argjson", "runID", "42",
             "--argjson", "runAttempt", "2", "-f", str(FILTER)],
            input=json.dumps(metadata), text=True, capture_output=True, check=False,
        )
        return result.returncode == 0

    def test_accepts_exact_released_toolchain_and_ci_identity(self):
        self.assertTrue(self.accepts(self.metadata))

    def test_rejects_altered_toolchain_and_provenance(self):
        for key, value in (
            ("xcodeVersion", "Xcode 26.3"),
            ("xcodeVersion", "Xcode 27.1"),
            ("xcodeBuild", "27A5252f"),
            ("xcodeBuild", "27A266b"),
            ("schema", "record-ci-app-v2"),
            ("runner", "self-hosted"),
            ("repository", "other/record"),
            ("commit", "c" * 40),
            ("workflow", ".github/workflows/other.yml"),
            ("runID", 43),
            ("runAttempt", 1),
            ("appVersion", "1.4.4"),
            ("buildNumber", "0"),
            ("modelDownloaderExecutableSHA256", "invalid"),
            ("executableSHA256", None),
        ):
            with self.subTest(key=key, value=value):
                self.assertFalse(self.accepts({**self.metadata, key: value}))

    def test_rejects_missing_and_extra_fields(self):
        for key in self.metadata:
            with self.subTest(missing=key):
                altered = self.metadata.copy()
                del altered[key]
                self.assertFalse(self.accepts(altered))
        self.assertFalse(self.accepts({**self.metadata, "unreviewed": True}))


if __name__ == "__main__":
    unittest.main()
