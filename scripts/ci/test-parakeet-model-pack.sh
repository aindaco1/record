#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/publish-parakeet-model.yml"
packager="$repo_root/scripts/release/package-parakeet-model.sh"
attribution="$repo_root/docs/models/PARAKEET_MODEL_ATTRIBUTION.md"

for required_fragment in \
    'MODEL_RELEASE_TAG: v1.3.0' \
    'MODEL_ASSET_NAME: Record-Parakeet-v3-aed0274.zip' \
    'environment: release' \
    'only the repository owner may publish the model pack' \
    'git tag -v "$MODEL_RELEASE_TAG"' \
    'huggingface_hub==0.36.2' \
    './scripts/setup/install-parakeet-model.sh' \
    './scripts/release/package-parakeet-model.sh' \
    'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8' \
    'gh release upload "$MODEL_RELEASE_TAG"'; do
    if ! grep -Fq "$required_fragment" "$workflow"; then
        echo "model-pack workflow is missing: $required_fragment" >&2
        exit 1
    fi
done

if grep -Fq -- '--clobber' "$workflow"; then
    echo "model-pack publication must not replace an existing immutable asset" >&2
    exit 1
fi

for required_fragment in \
    'ParakeetModelVerifier.swift' \
    'sourceRevision:' \
    'localFolderName:' \
    'model file failed SHA-256 verification' \
    'UPSTREAM_MODEL_CARD.md' \
    'LICENSE-CC-BY-4.0.txt' \
    'LICENSE-APACHE-2.0.txt' \
    'zip -X' \
    'unzip -tq'; do
    if ! grep -Fq "$required_fragment" "$packager"; then
        echo "model-pack script is missing: $required_fragment" >&2
        exit 1
    fi
done

for required_fragment in \
    'FluidInference/parakeet-tdt-0.6b-v3-coreml' \
    'aed02740059203c4a87495924f685de3722ae9ce' \
    'Creative Commons Attribution 4.0 International license' \
    'Model contents are not modified'; do
    if ! grep -Fq "$required_fragment" "$attribution"; then
        echo "model attribution is missing: $required_fragment" >&2
        exit 1
    fi
done

if git -C "$repo_root" ls-files | \
    grep -Eq '(^|/)(Encoder|Decoder|Preprocessor|JointDecisionv3)\.mlmodelc|Record-Parakeet.*\.zip$'; then
    echo "a model binary or generated model pack was added to Git history" >&2
    exit 1
fi

echo "Parakeet model-pack publication tests passed"
