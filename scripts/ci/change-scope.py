#!/usr/bin/env python3
"""Classify reviewed Markdown changes; uncertain input always needs full CI."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess

ROOT_DOCS = {"README.md", "CHANGELOG.md", "AGENTS.md", "CONTRIBUTING.md",
             "SUPPORT.md", "SECURITY.md", "PRIVACY.md", "CODE_OF_CONDUCT.md", "ROADMAP.md"}
PACKAGED_DOCS = {"docs/models/PARAKEET_MODEL_ATTRIBUTION.md"}


def is_documentation(path):
    parts = PurePosixPath(path).parts
    if not parts or ".." in parts or path.startswith("/") or "\\" in path:
        return False
    if path in PACKAGED_DOCS:
        return False
    return (path in ROOT_DOCS or path in {"containers/README.md", ".github/pull_request_template.md"}
            or (parts[0] == "docs" and path.endswith(".md")))


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def classify(root, base=None, head=None):
    """Include staged, unstaged and untracked changes unless comparing commits."""
    try:
        if base is None:
            base = git(root, "merge-base", "HEAD", "origin/main").decode().strip()
        base = git(root, "rev-parse", "--verify", base + "^{commit}").decode().strip()
        revisions = [base]
        if head:
            revisions.append(git(root, "rev-parse", "--verify", head + "^{commit}").decode().strip())
        fields = git(root, "diff", "--raw", "-z", "--no-renames", "--no-ext-diff",
                     "--no-textconv", *revisions, "--").split(b"\0")
        paths = []
        for index in range(0, len(fields) - 1, 2):
            metadata = fields[index].decode().split()
            path = os.fsdecode(fields[index + 1])
            if (len(metadata) != 5 or metadata[0] not in {":100644", ":000000"}
                    or metadata[1] not in {"100644", "000000"} or metadata[4] not in {"A", "D", "M"}):
                return False
            paths.append(path)
        if not head:
            for entry in git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
                if entry:
                    path = os.fsdecode(entry)
                    mode = (root / path).lstat().st_mode
                    if not stat.S_ISREG(mode) or mode & 0o111:
                        return False
                    paths.append(path)
        return bool(paths) and all(is_documentation(path) for path in paths)
    except (OSError, subprocess.CalledProcessError, UnicodeError, IndexError, ValueError):
        return False


def classify_event(root, event_name, event, sha):
    # Dispatches and schedules always build/scan, including documentation-only heads.
    if event_name not in {"push", "pull_request"}:
        return False
    try:
        if event_name == "push":
            base = event["before"]
        else:
            base = event["pull_request"]["base"]["sha"]
        if not base or not sha or set(base) == {"0"}:
            return False
        return classify(root, base, sha)
    except (KeyError, TypeError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Local comparison base; defaults to merge-base with origin/main")
    parser.add_argument("--head", help="Compare commits instead of the working tree")
    parser.add_argument("--github-event", action="store_true")
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--value", action="store_true", help="Print docs or full")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.github_event:
        if args.base or args.head:
            parser.error("--github-event cannot be combined with local revisions")
        try:
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        except (KeyError, OSError, ValueError):
            event = {}
        docs_only = classify_event(root, os.environ.get("GITHUB_EVENT_NAME"), event,
                                   os.environ.get("GITHUB_SHA"))
    else:
        if args.head and not args.base:
            parser.error("--head requires --base")
        docs_only = classify(root, args.base, args.head)
    if args.github_output:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write("docs_only=" + str(docs_only).lower() + "\n")
    print(("docs" if docs_only else "full") if args.value else json.dumps({"docs_only": docs_only}))


if __name__ == "__main__":
    main()
