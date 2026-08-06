#!/usr/bin/env bash
set -euo pipefail

local_dir=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--local-dir" ]]; then
        shift
        local_dir="$1"
    fi
    shift
done
test -n "$local_dir"

for bundle in Preprocessor Encoder Decoder JointDecisionv3; do
    mkdir -p "$local_dir/$bundle.mlmodelc/weights"
    printf 'fixture\n' > "$local_dir/$bundle.mlmodelc/coremldata.bin"
    printf '{}\n' > "$local_dir/$bundle.mlmodelc/metadata.json"
    printf 'fixture\n' > "$local_dir/$bundle.mlmodelc/model.mil"
    printf 'fixture\n' > "$local_dir/$bundle.mlmodelc/weights/weight.bin"
done
printf '{}\n' > "$local_dir/parakeet_vocab.json"
