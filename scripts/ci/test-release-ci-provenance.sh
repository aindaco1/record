#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci_workflow="$repo_root/.github/workflows/ci.yml"
release_workflow="$repo_root/.github/workflows/release.yml"
restore_script="$repo_root/scripts/release/restore-ci-app.sh"
required_runs_script="$repo_root/scripts/release/required-ci-runs.sh"

for required_fragment in \
    'actions: read' \
    'RELEASE_COMMIT=%s' \
    'Restore exact successful CI app and security evidence' \
    './scripts/release/restore-ci-app.sh' \
    './scripts/ci/release-source-gate.sh' \
    'Restore locked Sparkle release tool' \
    'swift package resolve' \
    'git diff --exit-code -- Package.resolved' \
    'test -x .build/artifacts/sparkle/Sparkle/bin/generate_appcast'; do
    if ! grep -Fq "$required_fragment" "$release_workflow"; then
        echo "release workflow is missing CI provenance control: $required_fragment" >&2
        exit 1
    fi
done
restore_tool_line="$(
    grep -nF 'Restore locked Sparkle release tool' "$release_workflow" \
        | cut -d: -f1
)"
generate_feed_line="$(
    grep -nF 'Generate signed update feed' "$release_workflow" \
        | cut -d: -f1
)"
if [[ ! "$restore_tool_line" =~ ^[1-9][0-9]*$ || \
      ! "$generate_feed_line" =~ ^[1-9][0-9]*$ || \
      "$restore_tool_line" -ge "$generate_feed_line" ]]; then
    echo "release workflow does not restore Sparkle before feed generation" >&2
    exit 1
fi
if grep -Fq 'run: ./scripts/ci/validate.sh' "$release_workflow" || \
    grep -Fq './scripts/release/build-app.sh' "$release_workflow"; then
    echo "release workflow still repeats an exact-commit build gate" >&2
    exit 1
fi
if ! grep -Fq './scripts/ci/source-contract-gate.sh' \
    "$repo_root/scripts/ci/release-source-gate.sh"; then
    echo "release source gate does not share the CI source contract" >&2
    exit 1
fi

for required_fragment in \
    'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8' \
    'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' \
    "github.event_name == 'push' && github.ref == 'refs/heads/main'" \
    './scripts/tools/package-ci-app.sh'; do
    if ! grep -Fq "$required_fragment" "$ci_workflow"; then
        echo "CI workflow is missing trusted app handoff control: $required_fragment" >&2
        exit 1
    fi
done

for required_fragment in \
    'scripts/release/required-ci-runs.sh' \
    'record-ci-app-v2' \
    'modelDownloaderInfoPlistSHA256' \
    'modelDownloaderExecutableSHA256' \
    "--signer-workflow \"github.com/\$repository/.github/workflows/ci.yml\"" \
    '--source-ref refs/heads/main' \
    "--source-digest \"\$commit\"" \
    '--deny-self-hosted-runners' \
    'scripts/tools/extract-ci-app.py'; do
    if ! grep -Fq -- "$required_fragment" "$restore_script"; then
        echo "CI app restore is missing provenance policy: $required_fragment" >&2
        exit 1
    fi
done

test_root="$(mktemp -d "${TMPDIR:-/tmp}/record-ci-runs-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT
mkdir "$test_root/bin"
cat > "$test_root/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" != "run list" ]]; then
    exit 64
fi
workflow=""
commit=""
repository=""
branch=""
event=""
status=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workflow) workflow="$2"; shift 2 ;;
        --commit) commit="$2"; shift 2 ;;
        --repo) repository="$2"; shift 2 ;;
        --branch) branch="$2"; shift 2 ;;
        --event) event="$2"; shift 2 ;;
        --status) status="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ "$commit" != "$FAKE_COMMIT" || "$repository" != "aindaco1/record" || \
      "$branch" != main || "$event" != push || "$status" != success ]]; then
    exit 64
fi
if [[ "$workflow" == CI ]]; then
    printf '[{"databaseId":40,"attempt":1,"conclusion":"success","event":"push","headBranch":"other","headSha":"%s","status":"completed"},{"databaseId":42,"attempt":2,"conclusion":"success","event":"push","headBranch":"main","headSha":"%s","status":"completed"}]\n' "$commit" "$commit"
elif [[ "$workflow" == CodeQL && "${FAKE_MISSING_CODEQL:-0}" != 1 ]]; then
    printf '[{"databaseId":51,"attempt":1,"conclusion":"success","event":"push","headBranch":"main","headSha":"%s","status":"completed"}]\n' "$commit"
else
    printf '[]\n'
fi
SH
chmod +x "$test_root/bin/gh"
commit="$(git -C "$repo_root" rev-parse HEAD)"
actual="$(
    PATH="$test_root/bin:$PATH" FAKE_COMMIT="$commit" \
        "$required_runs_script" aindaco1/record "$commit"
)"
if [[ "$actual" != $'42\t2\t51' ]]; then
    echo "exact-commit CI run selection returned: $actual" >&2
    exit 1
fi
if PATH="$test_root/bin:$PATH" FAKE_COMMIT="$commit" FAKE_MISSING_CODEQL=1 \
    "$required_runs_script" aindaco1/record "$commit" >/dev/null 2>&1; then
    echo "CI evidence gate accepted a missing CodeQL run" >&2
    exit 1
fi

echo "release CI provenance tests passed"
