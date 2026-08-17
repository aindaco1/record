#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="$repo_root/.build/release-artifacts/Record.app"

cd "$repo_root"
./scripts/release/build-app.sh
./scripts/ci/check-app-bundle.sh "$app_path"

# Sign and package outside the iCloud-backed workspace. File Provider may
# reattach Finder metadata immediately inside the checkout, even after xattr
# cleanup, while a temporary local bundle remains stable and verifiable.
signing_root="$(mktemp -d "${TMPDIR:-/tmp}/record-package-gate.XXXXXX")"
trap 'rm -rf "$signing_root"' EXIT
signing_app="$signing_root/Record.app"
ditto --norsrc --noextattr "$app_path" "$signing_app"
./scripts/release/sign-app.sh "$signing_app" - none
RECORD_APP_PATH="$signing_app" ./scripts/ci/verify-package.sh

# Exercise the complete signed-feed generator with a disposable matching key
# pair. The production private key exists only in the protected release
# environment, and Sparkle correctly refuses to sign an archive whose embedded
# public key does not match.
test_update_key_path="$signing_root/update-key.pem"
openssl genpkey -algorithm ED25519 -out "$test_update_key_path" 2>/dev/null
test_update_key="$({
    openssl pkey -in "$test_update_key_path" -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
test_update_public_key="$({
    openssl pkey -in "$test_update_key_path" -pubout -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
/usr/libexec/PlistBuddy \
    -c "Set :SUPublicEDKey $test_update_public_key" \
    "$signing_app/Contents/Info.plist"
./scripts/release/sign-app.sh "$signing_app" - none
RECORD_APP_PATH="$signing_app" ./scripts/release/package.sh >/dev/null
SPARKLE_ED25519_PRIVATE_KEY="$test_update_key" \
    RECORD_RELEASE_NOTES_PATH="$repo_root/docs/releases/1.0.0.md" \
    ./scripts/release/generate-appcast.sh "v${RECORD_VERSION:-0.0.0-dev}"
unset test_update_key test_update_public_key
./scripts/release/checksum-artifacts.sh
(cd .build/release-artifacts && shasum -a 256 -c SHA256SUMS)
