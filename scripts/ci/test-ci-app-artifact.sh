#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$repo_root/scripts/tools/extract-ci-app.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/record-ci-app-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

fixture="$test_root/fixture/record-ci-app/Record.app/Contents/Frameworks/Sparkle.framework/Versions"
mkdir -p "$fixture/A"
printf 'fixture\n' > "$fixture/A/payload"
ln -s A "$fixture/Current"
safe_archive="$test_root/safe.tar.gz"
COPYFILE_DISABLE=1 /usr/bin/tar -czf "$safe_archive" \
    -C "$test_root/fixture" record-ci-app
python3 "$extractor" "$safe_archive" "$test_root/safe-output"
test "$(cat "$test_root/safe-output/record-ci-app/Record.app/Contents/Frameworks/Sparkle.framework/Versions/Current/payload")" = fixture
test "$(readlink "$test_root/safe-output/record-ci-app/Record.app/Contents/Frameworks/Sparkle.framework/Versions/Current")" = A

python3 - "$test_root/traversal.tar.gz" "$test_root/escape-link.tar.gz" <<'PY'
import io
from pathlib import Path
import sys
import tarfile

traversal = Path(sys.argv[1])
with tarfile.open(traversal, "w:gz") as archive:
    member = tarfile.TarInfo("record-ci-app/../../outside")
    member.size = 1
    archive.addfile(member, io.BytesIO(b"x"))

escape = Path(sys.argv[2])
with tarfile.open(escape, "w:gz") as archive:
    root = tarfile.TarInfo("record-ci-app")
    root.type = tarfile.DIRTYPE
    archive.addfile(root)
    link = tarfile.TarInfo("record-ci-app/escape")
    link.type = tarfile.SYMTYPE
    link.linkname = "../../outside"
    archive.addfile(link)
PY
if python3 "$extractor" "$test_root/traversal.tar.gz" \
    "$test_root/traversal-output" >/dev/null 2>&1; then
    echo "CI app extractor accepted path traversal" >&2
    exit 1
fi
if python3 "$extractor" "$test_root/escape-link.tar.gz" \
    "$test_root/link-output" >/dev/null 2>&1; then
    echo "CI app extractor accepted an escaping symbolic link" >&2
    exit 1
fi

echo "CI app artifact extraction tests passed"
