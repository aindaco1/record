#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <owner/repository> <commit>" >&2
    exit 64
fi
repository="$1"
commit="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || \
      ! "$commit" =~ ^[a-f0-9]{40}$ || \
      "$(git -C "$repo_root" rev-parse HEAD)" != "$commit" ]]; then
    echo "invalid exact-commit CI evidence request" >&2
    exit 64
fi
for required_command in gh jq; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "missing CI evidence command: $required_command" >&2
        exit 1
    fi
done

required_run() {
    local workflow="$1"
    local required_job="$2"
    local runs selected run_id run_attempt jobs
    runs="$(
        gh run list --repo "$repository" --workflow "$workflow" \
            --commit "$commit" --branch main --status success \
            --limit 10 \
            --json databaseId,attempt,conclusion,event,headBranch,headSha,status
    )"
    selected="$(jq -er --arg commit "$commit" '
        [ .[] | select(
            .headSha == $commit and .headBranch == "main" and
            (.event == "push" or .event == "workflow_dispatch") and
            .status == "completed" and
            .conclusion == "success" and
            (.databaseId | type == "number") and .databaseId > 0 and
            (.attempt | type == "number") and .attempt > 0
        ) ]
        | if length == 0 then error("missing exact successful workflow run")
          else sort_by(.databaseId) | last | [.databaseId, .attempt] | @tsv
          end
    ' <<< "$runs")"
    run_id="${selected%%$'\t'*}"
    run_attempt="${selected#*$'\t'}"
    jobs="$(gh api --paginate \
        "repos/$repository/actions/runs/$run_id/attempts/$run_attempt/jobs?per_page=100")"
    if ! jq -es --arg required_job "$required_job" '
        [ .[].jobs[] | select(.name == $required_job) ]
        | length == 1 and all(.status == "completed" and .conclusion == "success")
    ' <<< "$jobs" >/dev/null; then
        echo "$workflow did not complete $required_job; run full CI and CodeQL on this main commit before releasing" >&2
        exit 1
    fi
    printf '%s\n' "$selected"
}

ci_run="$(required_run CI 'Build and package app')"
codeql_run="$(required_run CodeQL 'Analyze Swift')"
ci_run_id="${ci_run%%$'\t'*}"
ci_run_attempt="${ci_run#*$'\t'}"
codeql_run_id="${codeql_run%%$'\t'*}"
printf '%s\t%s\t%s\n' "$ci_run_id" "$ci_run_attempt" "$codeql_run_id"
