#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/record-model-installer.XXXXXX")"
cleanup() {
    case "$fixture_root" in
        "${TMPDIR:-/tmp}"/record-model-installer.*) rm -rf -- "$fixture_root" ;;
        *) echo "refusing unsafe fixture cleanup: $fixture_root" >&2 ;;
    esac
}
trap cleanup EXIT

fake_bin="$fixture_root/bin"
target="$fixture_root/cache/parakeet-tdt-0.6b-v3"
mkdir -p "$fake_bin"
fake_hf="$fake_bin/hf"
cp "$repo_root/scripts/ci/fixtures/fake-hf.sh" "$fake_hf"
chmod 0700 "$fake_hf"

PATH="$fake_bin:/usr/bin:/bin" \
    "$repo_root/scripts/setup/install-parakeet-model.sh" "$target"
test -s "$target/Encoder.mlmodelc/weights/weight.bin"
test -s "$target/JointDecisionv3.mlmodelc/model.mil"

# A complete target is idempotent and must not invoke the downloader again.
PATH="/usr/bin:/bin" "$repo_root/scripts/setup/install-parakeet-model.sh" "$target"

incomplete="$fixture_root/incomplete"
mkdir -p "$incomplete"
if PATH="$fake_bin:/usr/bin:/bin" \
    "$repo_root/scripts/setup/install-parakeet-model.sh" "$incomplete" >/dev/null 2>&1
then
    echo "installer accepted an incomplete existing target" >&2
    exit 1
fi

echo "model installer tests passed"
