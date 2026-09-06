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
    "github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')" \
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
cat > "$test_root/bin/gh" <<'PYTHON'
#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
mode = os.environ.get("FAKE_MODE", "push")
commit = os.environ["FAKE_COMMIT"]
if args[:2] == ["run", "list"]:
    def option(name):
        return args[args.index(name) + 1]
    assert option("--commit") == commit
    assert option("--repo") == "aindaco1/record"
    assert option("--branch") == "main"
    assert option("--status") == "success"
    assert "--event" not in args
    workflow = option("--workflow")
    if workflow == "CodeQL" and mode == "missing-codeql":
        print("[]")
        sys.exit()
    run = dict(databaseId=42 if workflow == "CI" else 51,
               attempt=2 if workflow == "CI" else 1, conclusion="success",
               event="workflow_dispatch" if mode == "manual" else "push",
               headBranch="main", headSha=commit, status="completed")
    if mode == "invalid-event":
        run["event"] = "pull_request"
    elif mode == "invalid-branch":
        run["headBranch"] = "other"
    elif mode == "invalid-head":
        run["headSha"] = "0" * 40
    elif mode == "invalid-attempt":
        run["attempt"] = 0
    print(json.dumps([run]))
elif args[:2] == ["api", "--paginate"]:
    endpoint = args[2]
    is_ci = endpoint == "repos/aindaco1/record/actions/runs/42/attempts/2/jobs?per_page=100"
    assert is_ci or endpoint == "repos/aindaco1/record/actions/runs/51/attempts/1/jobs?per_page=100"
    job = dict(name="Build and package app" if is_ci else "Analyze Swift",
               status="completed", conclusion="success")
    if mode == "skipped-ci" and is_ci or mode == "skipped-codeql" and not is_ci:
        job["conclusion"] = "skipped"
    elif mode == "failed-job":
        job["conclusion"] = "failure"
    jobs = [] if mode == "missing-job" else [job]
    if mode == "duplicate-job":
        jobs.append(job)
    # Exercise the paginated response stream and ignore unrelated green jobs.
    print(json.dumps({"jobs": [dict(name="Swift tests and arm64 build", status="completed", conclusion="success")]}))
    print(json.dumps({"jobs": jobs}))
else:
    sys.exit(64)
PYTHON
chmod +x "$test_root/bin/gh"
commit="$(git -C "$repo_root" rev-parse HEAD)"
for mode in push manual; do
    actual="$(
        PATH="$test_root/bin:$PATH" FAKE_COMMIT="$commit" FAKE_MODE="$mode" \
            "$required_runs_script" aindaco1/record "$commit"
    )"
    if [[ "$actual" != $'42\t2\t51' ]]; then
        echo "exact-commit CI run selection returned: $actual" >&2
        exit 1
    fi
done
for mode in missing-codeql skipped-ci skipped-codeql missing-job duplicate-job \
    failed-job invalid-event invalid-branch invalid-head invalid-attempt; do
    if PATH="$test_root/bin:$PATH" FAKE_COMMIT="$commit" FAKE_MODE="$mode" \
        "$required_runs_script" aindaco1/record "$commit" >/dev/null 2>&1; then
        echo "CI evidence gate accepted invalid evidence: $mode" >&2
        exit 1
    fi
done

echo "release CI provenance tests passed"
