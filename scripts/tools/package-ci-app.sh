#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "usage: $0 <absolute-Record.app> <absolute-output.tar.gz> <owner/repository> <commit> <run-id> <run-attempt>" >&2
    exit 64
fi
app_path="$1"
archive="$2"
repository="$3"
commit="$4"
run_id="$5"
run_attempt="$6"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_app="$repo_root/.build/release-artifacts/Record.app"

if [[ "$app_path" != "$expected_app" || ! -d "$app_path" || -L "$app_path" || \
      "$archive" != /* || -e "$archive" || -L "$archive" || \
      ! -d "$(dirname "$archive")" || -L "$(dirname "$archive")" || \
      ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || \
      ! "$commit" =~ ^[a-f0-9]{40}$ || \
      ! "$run_id" =~ ^[1-9][0-9]*$ || ! "$run_attempt" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid CI app artifact input" >&2
    exit 64
fi
for required_command in jq python3 shasum; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "missing CI app packaging command: $required_command" >&2
        exit 1
    fi
done
if [[ "$(git -C "$repo_root" rev-parse HEAD)" != "$commit" ]] || \
    ! git -C "$repo_root" diff --quiet -- . || \
    ! git -C "$repo_root" diff --cached --quiet -- .; then
    echo "CI app checkout is not the exact clean source commit" >&2
    exit 1
fi

"$repo_root/scripts/ci/check-app-bundle.sh" "$app_path"
app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
    "$app_path/Contents/Info.plist")"
build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - \
    "$app_path/Contents/Info.plist")"
if [[ "$app_version" != "0.0.0-ci" || ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "CI app has unexpected version metadata" >&2
    exit 1
fi
if /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "CI handoff app must remain unsigned" >&2
    exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/record-ci-app-package.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
bundle_root="$work_root/record-ci-app"
mkdir "$bundle_root"
ditto --norsrc --noextattr "$app_path" "$bundle_root/Record.app"

xcode_version_output="$(xcodebuild -version)"
xcode_version="${xcode_version_output%%$'\n'*}"
package_resolved_hash="$(shasum -a 256 "$repo_root/Package.resolved" | awk '{print $1}')"
build_app_hash="$(shasum -a 256 "$repo_root/scripts/release/build-app.sh" | awk '{print $1}')"
stamp_app_hash="$(shasum -a 256 "$repo_root/scripts/release/stamp-app.sh" | awk '{print $1}')"
bundle_check_hash="$(shasum -a 256 "$repo_root/scripts/ci/check-app-bundle.sh" | awk '{print $1}')"
source_plist_hash="$(shasum -a 256 "$repo_root/Sources/Record/Info.plist" | awk '{print $1}')"
executable_hash="$(shasum -a 256 "$bundle_root/Record.app/Contents/MacOS/record" | awk '{print $1}')"
model_downloader_info_hash="$(
    shasum -a 256 \
        "$repo_root/Sources/RecordModelDownloaderService/Info.plist" \
        | awk '{print $1}'
)"
model_downloader_executable_hash="$(
    shasum -a 256 \
        "$bundle_root/Record.app/Contents/XPCServices/RecordModelDownloader.xpc/Contents/MacOS/record-model-downloader" \
        | awk '{print $1}'
)"
jq -n \
    --arg repository "$repository" \
    --arg commit "$commit" \
    --argjson runID "$run_id" \
    --argjson runAttempt "$run_attempt" \
    --arg xcodeVersion "$xcode_version" \
    --arg packageResolvedSHA256 "$package_resolved_hash" \
    --arg buildAppSHA256 "$build_app_hash" \
    --arg stampAppSHA256 "$stamp_app_hash" \
    --arg bundleCheckSHA256 "$bundle_check_hash" \
    --arg sourceInfoPlistSHA256 "$source_plist_hash" \
    --arg executableSHA256 "$executable_hash" \
    --arg modelDownloaderInfoPlistSHA256 "$model_downloader_info_hash" \
    --arg modelDownloaderExecutableSHA256 "$model_downloader_executable_hash" \
    --arg appVersion "$app_version" \
    --arg buildNumber "$build_number" \
    '{
      schema: "record-ci-app-v2",
      repository: $repository,
      commit: $commit,
      workflow: ".github/workflows/ci.yml",
      runID: $runID,
      runAttempt: $runAttempt,
      runner: "github-hosted",
      xcodeVersion: $xcodeVersion,
      packageResolvedSHA256: $packageResolvedSHA256,
      buildAppSHA256: $buildAppSHA256,
      stampAppSHA256: $stampAppSHA256,
      bundleCheckSHA256: $bundleCheckSHA256,
      sourceInfoPlistSHA256: $sourceInfoPlistSHA256,
      executableSHA256: $executableSHA256,
      modelDownloaderInfoPlistSHA256: $modelDownloaderInfoPlistSHA256,
      modelDownloaderExecutableSHA256: $modelDownloaderExecutableSHA256,
      appVersion: $appVersion,
      buildNumber: $buildNumber
    }' > "$bundle_root/metadata.json"
chmod 0644 "$bundle_root/metadata.json"

COPYFILE_DISABLE=1 /usr/bin/tar -czf "$archive" -C "$work_root" record-ci-app
chmod 0644 "$archive"
verification_root="$work_root/verification"
python3 "$repo_root/scripts/tools/extract-ci-app.py" "$archive" "$verification_root"
"$repo_root/scripts/ci/check-app-bundle.sh" \
    "$verification_root/record-ci-app/Record.app"
echo "$archive"
