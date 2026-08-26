#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <owner/repository> <commit> <absolute-Record.app-destination>" >&2
    exit 64
fi
repository="$1"
commit="$2"
app_destination="$3"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_destination="$repo_root/.build/release-artifacts/Record.app"
artifacts_root="$(dirname "$expected_destination")"

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || \
      ! "$commit" =~ ^[a-f0-9]{40}$ || \
      "$app_destination" != "$expected_destination" || \
      -e "$app_destination" || -L "$app_destination" || \
      -L "$repo_root/.build" || -L "$artifacts_root" ]]; then
    echo "invalid verified CI app destination" >&2
    exit 64
fi
for required_command in gh jq python3 shasum; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "missing CI app restore command: $required_command" >&2
        exit 1
    fi
done

required_runs="$(
    "$repo_root/scripts/release/required-ci-runs.sh" "$repository" "$commit"
)"
ci_run_id="${required_runs%%$'\t'*}"
remaining_runs="${required_runs#*$'\t'}"
ci_run_attempt="${remaining_runs%%$'\t'*}"
codeql_run_id="${remaining_runs#*$'\t'}"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/record-ci-app-restore.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
artifact_name="record-verified-app-$commit"
gh run download "$ci_run_id" --repo "$repository" \
    --name "$artifact_name" --dir "$work_root/download"
archive="$work_root/download/record-ci-app-$commit.tar.gz"
if [[ ! -f "$archive" || -L "$archive" ]]; then
    echo "exact CI app artifact is missing or unsafe" >&2
    exit 1
fi

gh attestation verify "$archive" \
    --repo "$repository" \
    --signer-workflow "github.com/$repository/.github/workflows/ci.yml" \
    --source-ref refs/heads/main \
    --source-digest "$commit" \
    --deny-self-hosted-runners >/dev/null

extract_root="$work_root/extracted"
python3 "$repo_root/scripts/tools/extract-ci-app.py" "$archive" "$extract_root"
bundle_root="$extract_root/record-ci-app"
metadata="$bundle_root/metadata.json"
restored_app="$bundle_root/Record.app"
if [[ ! -f "$metadata" || -L "$metadata" ]] || ! jq -e \
    --arg repository "$repository" \
    --arg commit "$commit" \
    --argjson runID "$ci_run_id" \
    --argjson runAttempt "$ci_run_attempt" '
      (keys | sort) == [
        "appVersion", "buildAppSHA256", "buildNumber", "bundleCheckSHA256",
        "commit", "executableSHA256", "packageResolvedSHA256", "repository",
        "runAttempt", "runID", "runner", "schema", "sourceInfoPlistSHA256",
        "stampAppSHA256", "workflow", "xcodeVersion"
      ] and
      .schema == "record-ci-app-v1" and
      .repository == $repository and .commit == $commit and
      .workflow == ".github/workflows/ci.yml" and
      .runID == $runID and .runAttempt == $runAttempt and
      .runner == "github-hosted" and .xcodeVersion == "Xcode 26.3" and
      .appVersion == "0.0.0-ci" and
      (.buildNumber | test("^[1-9][0-9]*$")) and
      ([
        .packageResolvedSHA256, .buildAppSHA256, .stampAppSHA256,
        .bundleCheckSHA256, .sourceInfoPlistSHA256, .executableSHA256
      ] | all(type == "string" and test("^[a-f0-9]{64}$")))
    ' "$metadata" >/dev/null; then
    echo "CI app provenance metadata is invalid" >&2
    exit 1
fi

assert_source_hash() {
    local metadata_key="$1"
    local source_path="$2"
    local actual expected
    actual="$(shasum -a 256 "$source_path" | awk '{print $1}')"
    expected="$(jq -r ".$metadata_key" "$metadata")"
    if [[ "$actual" != "$expected" ]]; then
        echo "CI app provenance does not match $source_path" >&2
        exit 1
    fi
}
assert_source_hash packageResolvedSHA256 "$repo_root/Package.resolved"
assert_source_hash buildAppSHA256 "$repo_root/scripts/release/build-app.sh"
assert_source_hash stampAppSHA256 "$repo_root/scripts/release/stamp-app.sh"
assert_source_hash bundleCheckSHA256 "$repo_root/scripts/ci/check-app-bundle.sh"
assert_source_hash sourceInfoPlistSHA256 "$repo_root/Sources/Record/Info.plist"
restored_executable_hash="$(
    shasum -a 256 "$restored_app/Contents/MacOS/record" | awk '{print $1}'
)"
if [[ "$restored_executable_hash" != "$(jq -r '.executableSHA256' "$metadata")" ]]; then
    echo "restored CI app executable does not match its provenance" >&2
    exit 1
fi
"$repo_root/scripts/ci/check-app-bundle.sh" "$restored_app"
if /usr/bin/codesign --verify --deep --strict "$restored_app" >/dev/null 2>&1; then
    echo "restored CI handoff app must remain unsigned" >&2
    exit 1
fi

mkdir -p "$(dirname "$app_destination")"
mv "$restored_app" "$app_destination"
"$repo_root/scripts/ci/check-app-bundle.sh" "$app_destination"
echo "restored verified CI app from CI run $ci_run_id and CodeQL run $codeql_run_id"
