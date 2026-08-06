#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_root="${1:-$repo_root/.github/workflows}"
failed=0

if [[ ! -d "$workflow_root" ]]; then
    echo "workflow directory does not exist: $workflow_root" >&2
    exit 1
fi

shopt -s nullglob
workflow_files=("$workflow_root"/*.yml "$workflow_root"/*.yaml)
if [[ ${#workflow_files[@]} -eq 0 ]]; then
    echo "no GitHub Actions workflows found" >&2
    exit 1
fi

for workflow in "${workflow_files[@]}"; do
    while IFS= read -r line; do
        reference="${line#*uses:}"
        reference="${reference%%#*}"
        reference="${reference#"${reference%%[![:space:]]*}"}"
        reference="${reference%"${reference##*[![:space:]]}"}"
        reference="${reference#\"}"
        reference="${reference%\"}"
        reference="${reference#\'}"
        reference="${reference%\'}"

        case "$reference" in
            ./*) continue ;;
            docker://*@sha256:[0-9a-f][0-9a-f]*)
                digest="${reference##*@sha256:}"
                if [[ "$digest" =~ ^[0-9a-f]{64}$ ]]; then
                    continue
                fi
                ;;
            *@[0-9a-f][0-9a-f]*)
                revision="${reference##*@}"
                if [[ "$revision" =~ ^[0-9a-f]{40}$ ]]; then
                    continue
                fi
                ;;
        esac

        echo "unpinned action in ${workflow#"$repo_root/"}: $reference" >&2
        failed=1
    done < <(grep -E '^[[:space:]-]*uses:[[:space:]]*' "$workflow" || true)
done

exit "$failed"
