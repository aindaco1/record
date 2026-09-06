#!/usr/bin/env python3
"""Check repository Markdown structure and local links without network access."""
import html
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit


def prose(text):
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    lines, fence = [], None
    for line in text.splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
        elif marker:
            fence = marker[1]
        else:
            lines.append(line)
    if fence:
        raise ValueError("unclosed fenced code block")
    return "\n".join(lines)


def anchors(text):
    result = set(re.findall(r'(?:id|name)=["\']([^"\']+)["\']', text))
    counts = {}
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)\s*#*$", line)
        title = match[1] if match else None
        if title is None and index and re.fullmatch(r" {0,3}(?:=+|-+)\s*", line):
            title = lines[index - 1].strip()
        if not title:
            continue
        title = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", title)
        title = html.unescape(re.sub(r"<[^>]*>", "", title))
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(slug if count == 0 else f"{slug}-{count}")
    return result


def destinations(text):
    # Ignore inline code, but retain code labels when extracting heading anchors.
    text = re.sub(r"(`+).*?\1", "", text)
    destination = r'(<[^>]+>|(?:\\.|[^\s()]|\([^)]*\))+)'
    definitions = {}
    for match in re.finditer(r"^ {0,3}\[([^]\n]+)\]:\s*" + destination, text, re.M):
        definitions[" ".join(match[1].lower().split())] = match[2].strip("<>")
    text = re.sub(r"^ {0,3}\[[^]\n]+\]:.*$", "", text, flags=re.M)
    inline = re.compile(r"\[[^]\n]*\]\(\s*" + destination + r'(?:\s+["\'][^"\']*["\'])?\s*\)')
    for match in inline.finditer(text):
        yield match[1].strip("<>")
    text = inline.sub("", text)
    references = re.compile(r"\[([^]\n]+)\]\[([^]\n]*)\]")
    for match in references.finditer(text):
        key = " ".join((match[2] or match[1]).lower().split())
        if key not in definitions:
            raise ValueError(f"undefined link reference: {key}")
        yield definitions[key]
    text = references.sub("", text)
    for match in re.finditer(r"\[([^]\n]+)\]", text):
        key = " ".join(match[1].lower().split())
        if key in definitions:
            yield definitions[key]


def validate(root):
    names = subprocess.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others",
                                     "--exclude-standard", "-z"]).split(b"\0")
    documents = sorted({root / entry.decode() for entry in names if entry.endswith(b".md")
                        and ((root / entry.decode()).exists() or (root / entry.decode()).is_symlink())})
    errors, checked, cache = [], 0, {}

    def read_document(path):
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("Markdown must be a regular file inside the repository")
        if path not in cache:
            raw = path.read_text(encoding="utf-8")
            for number, line in enumerate(raw.splitlines(), 1):
                if line != line.rstrip(" \t"):
                    raise ValueError(f"trailing whitespace on line {number}")
            cache[path] = prose(raw)
        return cache[path]

    for document in documents:
        try:
            text = read_document(document)
            for url in destinations(text):
                parsed = urlsplit(html.unescape(url))
                if parsed.scheme or parsed.netloc:
                    continue
                checked += 1
                decoded = re.sub(r"\\([() ])", r"\1", unquote(parsed.path))
                target = document.parent / decoded if decoded else document
                resolved = target.resolve()
                if not resolved.is_relative_to(root.resolve()):
                    errors.append(f"{document.relative_to(root)}: link leaves repository: {url}")
                elif not target.exists():
                    errors.append(f"{document.relative_to(root)}: missing target: {url}")
                elif parsed.fragment and target.suffix == ".md":
                    if unquote(parsed.fragment) not in anchors(read_document(target)):
                        errors.append(f"{document.relative_to(root)}: missing heading: {url}")
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f"{document.relative_to(root)}: {error}")
    return len(documents), checked, errors


def main():
    root = Path(__file__).resolve().parents[2]
    count, checked, errors = validate(root)
    for error in errors:
        print(error)
    print(f"Checked {checked} local links and anchors in {count} Markdown files; {len(errors)} errors.")
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
