"""Offline fixtures for documentation routing, links and required CI results."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


scope = module("change-scope")
docs = module("validate-docs")


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.filemode", "true")
        self.write("README.md", "# Record\n")
        self.write("Sources/app.swift", "// fixture\n")
        self.base = self.commit()
        self.git("update-ref", "refs/remotes/origin/main", self.base)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args],
                                       stderr=subprocess.DEVNULL).decode().strip()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture")
        return self.git("rev-parse", "HEAD")


class ChangeScopeTests(RepositoryTest):
    def test_allowlist_excludes_packaged_and_executable_inputs(self):
        for name in ("README.md", "AGENTS.md", "CHANGELOG.md", "docs/releases/1.5.0.md",
                     "docs/guide.md", "containers/README.md", ".github/pull_request_template.md"):
            with self.subTest(name=name):
                self.assertTrue(scope.is_documentation(name))
        for name in ("LICENSE", "THIRD_PARTY_NOTICES.md", "docs/models/PARAKEET_MODEL_ATTRIBUTION.md",
                     "docs/fixture.json", "scripts/check.md", "Sources/app.swift", "Package.resolved",
                     ".github/workflows/ci.yml", "unknown.md", "docs/../Sources/app.md", "/docs/a.md"):
            with self.subTest(name=name):
                self.assertFalse(scope.is_documentation(name))

    def test_local_combines_committed_staged_unstaged_and_untracked(self):
        self.write("README.md", "# Committed\n")
        self.commit()
        self.write("docs/staged.md", "# Staged\n")
        self.git("add", ".")
        self.write("README.md", "# Unstaged\n")
        self.write("docs/untracked.md", "# Untracked\n")
        self.assertTrue(scope.classify(self.root))
        self.write("Sources/untracked.swift", "// code\n")
        self.assertFalse(scope.classify(self.root))

    def test_empty_and_missing_history_require_full(self):
        self.assertFalse(scope.classify(self.root))
        self.write("README.md", "# Changed\n")
        self.assertFalse(scope.classify(self.root, "missing-ref"))
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assertFalse(scope.classify(self.root))

    def test_mode_and_symlink_changes_require_full(self):
        (self.root / "README.md").chmod(0o755)
        self.assertFalse(scope.classify(self.root))
        (self.root / "README.md").chmod(0o644)
        (self.root / "docs").mkdir()
        (self.root / "docs/link.md").symlink_to("../README.md")
        self.assertFalse(scope.classify(self.root))
        (self.root / "docs/link.md").unlink()
        self.write("docs/script.md", "# executable\n").chmod(0o755)
        self.assertFalse(scope.classify(self.root))

    def test_source_rename_cannot_hide_in_docs(self):
        (self.root / "docs").mkdir()
        self.git("mv", "Sources/app.swift", "docs/app.md")
        self.assertFalse(scope.classify(self.root))

    def test_markdown_rename_and_deletion(self):
        (self.root / "docs").mkdir()
        self.git("mv", "README.md", "docs/overview.md")
        self.assertTrue(scope.classify(self.root))
        self.commit()
        self.git("rm", "docs/overview.md")
        self.assertTrue(scope.classify(self.root))

    def test_complete_push_range_includes_earlier_source_change(self):
        self.write("Sources/app.swift", "// changed code\n")
        previous = self.commit()
        self.write("README.md", "# Changed\n")
        head = self.commit()
        self.assertTrue(scope.classify_event(self.root, "push", {"before": previous}, head))
        self.assertFalse(scope.classify_event(self.root, "push", {"before": self.base}, head))

    def test_event_boundaries(self):
        self.write("README.md", "# Changed\n")
        head = self.commit()
        event = {"before": self.base, "pull_request": {"base": {"sha": self.base}}}
        self.assertTrue(scope.classify_event(self.root, "pull_request", event, head))
        for name in ("workflow_dispatch", "schedule", "unknown"):
            self.assertFalse(scope.classify_event(self.root, name, event, head))
        for event in ({}, {"before": "0" * 40}, {"before": "missing"}, [], None):
            self.assertFalse(scope.classify_event(self.root, "push", event, head))
        self.assertFalse(scope.classify_event(self.root, "push", {"before": self.base}, None))


class DocumentationTests(RepositoryTest):
    def test_links_headings_references_and_code_examples(self):
        self.write("docs/My guide.md", "# **Hello** `World`\n# Repeat\n# Repeat\nSetext\n======\n")
        self.write("docs/image.svg", "<svg/>\n")
        self.write("README.md", """# Record
[heading](<docs/My guide.md#hello-world>)
[duplicate](docs/My%20guide.md#repeat-1)
[setext][guide]
[guide][] and [guide]
![image](docs/image.svg)
[site](https://example.invalid/unreachable)
`[inline example](missing.md)`
<!-- [comment](missing.md) -->
```markdown
[fenced example](missing.md)
```
[guide]: <docs/My guide.md#setext> "Guide"
""")
        count, checked, errors = docs.validate(self.root)
        self.assertEqual((count, checked, errors), (2, 6, []))

    def test_broken_targets_and_anchors_fail(self):
        self.write("README.md", "# Record\n[bad](missing.md)\n[bad](#missing)\n")
        self.assertEqual(len(docs.validate(self.root)[2]), 2)

    def test_unclosed_fence_and_undefined_reference_fail(self):
        for text in ("```swift\n", "[text][missing]\n"):
            self.write("README.md", text)
            self.assertTrue(docs.validate(self.root)[2])

    def test_committed_trailing_whitespace_fails_in_clean_ci_checkout(self):
        self.write("README.md", "# Record \n")
        self.commit()
        self.assertIn("trailing whitespace", docs.validate(self.root)[2][0])

    def test_outside_repository_and_symlink_fail(self):
        self.write("README.md", "[outside](../outside.md)\n")
        self.assertIn("leaves repository", docs.validate(self.root)[2][0])
        self.write("README.md", "# Record\n")
        (self.root / "docs").mkdir()
        (self.root / "docs/link.md").symlink_to("../README.md")
        self.assertTrue(docs.validate(self.root)[2])
        (self.root / "docs/link.md").unlink()
        (self.root / "docs/link.md").symlink_to("../missing.md")
        self.assertTrue(docs.validate(self.root)[2])


class EntryPointTests(RepositoryTest):
    def test_docs_path_does_not_invoke_full_gate_and_full_flag_does(self):
        for name in ("validate.sh", "validate-docs.sh", "change-scope.py", "validate-docs.py"):
            target = self.root / "scripts/ci" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SCRIPTS / name, target)
        # A deliberate failure proves the full path was entered without building an app.
        self.write("scripts/ci/source-contract-gate.sh", "#!/bin/sh\nexit 93\n").chmod(0o755)
        base = self.commit()
        self.git("update-ref", "refs/remotes/origin/main", base)
        self.write("README.md", "# Documentation change\n")
        command = [str(self.root / "scripts/ci/validate.sh")]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run(command + ["--full"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 93, result.stdout + result.stderr)
        self.write("README.md", "[broken](missing.md)\n")
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_required_result_rejects_failed_or_skipped_work(self):
        cases = (("success", "true", "skipped", True), ("success", "false", "success", True),
                 ("failure", "true", "skipped", False), ("cancelled", "false", "success", False),
                 ("success", "false", "failure", False), ("success", "false", "skipped", False),
                 ("success", "", "skipped", False), ("success", "true", "cancelled", False))
        for scope_result, docs_only, build_result, expected in cases:
            with self.subTest(case=(scope_result, docs_only, build_result)):
                result = subprocess.run([str(SCRIPTS / "check-validation-result.sh"),
                                         scope_result, docs_only, build_result], capture_output=True)
                self.assertEqual(result.returncode == 0, expected)


if __name__ == "__main__":
    unittest.main()
