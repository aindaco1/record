#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 /absolute/path/to/parakeet-model /absolute/path/to/output.zip" >&2
    exit 2
fi

source_model="$1"
output_zip="$2"
output_checksum="${output_zip}.sha256"

if [[ "$source_model" != /* || "$output_zip" != /* ]]; then
    echo "model source and output ZIP must use absolute paths" >&2
    exit 2
fi
if [[ ! -d "$source_model" ]]; then
    echo "model source does not exist: $source_model" >&2
    exit 1
fi
if [[ -e "$output_zip" || -e "$output_checksum" ]]; then
    echo "refusing to overwrite an existing model-pack artifact" >&2
    exit 1
fi

for tool in curl ruby shasum stat unzip zip; do
    if ! command -v "$tool" >/dev/null; then
        echo "required packaging tool is unavailable: $tool" >&2
        exit 1
    fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest_source="$repo_root/Sources/RecordSpeech/ParakeetModelVerifier.swift"
attribution_source="$repo_root/docs/models/PARAKEET_MODEL_ATTRIBUTION.md"

source_revision="$(
    sed -n 's/.*sourceRevision: "\([^"]*\)".*/\1/p' "$manifest_source" | head -n 1
)"
local_folder_name="$(
    sed -n 's/.*localFolderName: "\([^"]*\)".*/\1/p' "$manifest_source" | head -n 1
)"
fluid_audio_revision="$(
    ruby -rjson -e '
      resolved = JSON.parse(File.read(ARGV.fetch(0)))
      pin = resolved.fetch("pins").find { |candidate| candidate.fetch("identity") == "fluidaudio" }
      abort "FluidAudio pin is missing" unless pin
      puts pin.fetch("state").fetch("revision")
    ' "$repo_root/Package.resolved"
)"
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ || -z "$local_folder_name" || \
      ! "$fluid_audio_revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "could not resolve pinned model packaging metadata" >&2
    exit 1
fi

output_parent="$(dirname "$output_zip")"
mkdir -p "$output_parent"
package_root="$(mktemp -d "${TMPDIR:-/tmp}/record-parakeet-pack.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$package_root"
}
trap cleanup EXIT

bundle_name="Record-Parakeet-v3-${source_revision:0:7}"
bundle_root="$package_root/$bundle_name"
packaged_model="$bundle_root/$local_folder_name"
manifest="$package_root/manifest.tsv"
mkdir -p "$packaged_model"

ruby -ne '
  if $_ =~ /\.init\(path: "([^"]+)", size: ([\d_]+), sha256: "([^"]+)"\)/
    puts [$1, $2.delete("_"), $3].join("\t")
  end
' "$manifest_source" > "$manifest"

verified=0
while IFS=$'\t' read -r relative expected_size expected_sha; do
    case "$relative" in
        /* | ../* | */../*)
            echo "unsafe path in model manifest: $relative" >&2
            exit 1
            ;;
    esac
    input="$source_model/$relative"
    if [[ ! -f "$input" || -L "$input" ]]; then
        echo "missing or unsafe model file: $relative" >&2
        exit 1
    fi
    actual_size="$(stat -f '%z' "$input")"
    if [[ "$actual_size" != "$expected_size" ]]; then
        echo "model file has the wrong size: $relative" >&2
        exit 1
    fi
    actual_sha="$(shasum -a 256 "$input" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "model file failed SHA-256 verification: $relative" >&2
        exit 1
    fi
    output="$packaged_model/$relative"
    mkdir -p "$(dirname "$output")"
    COPYFILE_DISABLE=1 cp -p "$input" "$output"
    verified=$((verified + 1))
done < "$manifest"
if [[ "$verified" -ne 17 ]]; then
    echo "expected 17 verified model files, found $verified" >&2
    exit 1
fi

COPYFILE_DISABLE=1 cp "$attribution_source" "$bundle_root/MODEL-ATTRIBUTION.md"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/raw/$source_revision/README.md" \
    --output "$bundle_root/UPSTREAM_MODEL_CARD.md"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    "https://creativecommons.org/licenses/by/4.0/legalcode.txt" \
    --output "$bundle_root/LICENSE-CC-BY-4.0.txt"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    "https://raw.githubusercontent.com/FluidInference/FluidAudio/$fluid_audio_revision/LICENSE" \
    --output "$bundle_root/LICENSE-APACHE-2.0.txt"

find "$bundle_root" -type d -exec chmod 755 {} +
find "$bundle_root" -type f -exec chmod 644 {} +
find "$bundle_root" -exec touch -t 202604300000 {} +
(
    cd "$package_root"
    find "$bundle_name" -print | LC_ALL=C sort | zip -X -q "$output_zip" -@
)
unzip -tq "$output_zip"

archive_sha="$(shasum -a 256 "$output_zip" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$(basename "$output_zip")" > "$output_checksum"
echo "Packaged $verified verified Parakeet files: $output_zip"
echo "SHA-256: $archive_sha"
