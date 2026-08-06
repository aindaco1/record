#!/usr/bin/env bash
set -euo pipefail

model_repo="FluidInference/parakeet-tdt-0.6b-v3-coreml"
model_revision="aed02740059203c4a87495924f685de3722ae9ce"
bundle_id="com.aindaco.record"

record_user_home="${RECORD_USER_HOME:-}"
if [[ -z "$record_user_home" ]]; then
    record_user_home="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
fi
# FluidAudio's Repo.folderName intentionally strips the remote repository's
# "-coreml" suffix when it builds the local cache path.
default_target="$record_user_home/Library/Containers/$bundle_id/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"
target="${1:-$default_target}"

if [[ "$target" != /* ]]; then
    echo "model target must be an absolute path: $target" >&2
    exit 2
fi

required_paths=(
    "Preprocessor.mlmodelc/coremldata.bin"
    "Preprocessor.mlmodelc/metadata.json"
    "Preprocessor.mlmodelc/model.mil"
    "Preprocessor.mlmodelc/weights/weight.bin"
    "Encoder.mlmodelc/coremldata.bin"
    "Encoder.mlmodelc/metadata.json"
    "Encoder.mlmodelc/model.mil"
    "Encoder.mlmodelc/weights/weight.bin"
    "Decoder.mlmodelc/coremldata.bin"
    "Decoder.mlmodelc/metadata.json"
    "Decoder.mlmodelc/model.mil"
    "Decoder.mlmodelc/weights/weight.bin"
    "JointDecisionv3.mlmodelc/coremldata.bin"
    "JointDecisionv3.mlmodelc/metadata.json"
    "JointDecisionv3.mlmodelc/model.mil"
    "JointDecisionv3.mlmodelc/weights/weight.bin"
    "parakeet_vocab.json"
)

model_is_complete() {
    local root="$1"
    local path
    for path in "${required_paths[@]}"; do
        if [[ ! -s "$root/$path" ]]; then
            return 1
        fi
    done
}

if [[ -e "$target" ]]; then
    if model_is_complete "$target"; then
        echo "Parakeet v3 is already installed at $target"
        exit 0
    fi
    echo "refusing to overwrite an incomplete model directory: $target" >&2
    echo "move it aside, then rerun this installer" >&2
    exit 1
fi

if ! command -v hf >/dev/null; then
    echo "the Hugging Face 'hf' CLI is required to install the development model" >&2
    exit 1
fi

target_parent="$(dirname "$target")"
mkdir -p "$target_parent"
staging_root="$(mktemp -d "$target_parent/.record-parakeet.XXXXXX")"
cleanup() {
    if [[ -n "${staging_root:-}" && -d "$staging_root" ]]; then
        rm -rf -- "$staging_root"
    fi
}
trap cleanup EXIT
staged_model="$staging_root/model"

hf download "$model_repo" \
    --revision "$model_revision" \
    --local-dir "$staged_model" \
    --include \
    'Preprocessor.mlmodelc/*' \
    'Encoder.mlmodelc/*' \
    'Decoder.mlmodelc/*' \
    'JointDecisionv3.mlmodelc/*' \
    'parakeet_vocab.json'

if ! model_is_complete "$staged_model"; then
    echo "downloaded model is incomplete; target was not changed" >&2
    exit 1
fi

mv "$staged_model" "$target"
echo "Installed pinned Parakeet v3 model at $target"
