#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_svg="$repo_root/Sources/Record/Resources/AppIcon.svg"
output_icns="$repo_root/Sources/Record/Resources/Record.icns"

if ! command -v magick >/dev/null; then
    echo "ImageMagick is required to regenerate Record.icns" >&2
    exit 1
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/record-icon.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
iconset="$temporary_root/Record.iconset"
mkdir -p "$iconset"

# Preserve the supplied monochrome artwork exactly, while placing it on the
# opaque rounded white canvas macOS app icons need for dark and light desktop
# appearances. The source SVG remains the canonical editable asset.
magick -size 1024x1024 canvas:none \
    -fill white -draw 'roundrectangle 32,32 992,992 210,210' \
    "$temporary_root/background.png"
magick -background none "$source_svg" -resize 1024x1024 \
    "$temporary_root/artwork.png"
magick "$temporary_root/background.png" "$temporary_root/artwork.png" \
    -composite "$temporary_root/master.png"

render() {
    local pixels="$1"
    local filename="$2"
    magick "$temporary_root/master.png" -resize "${pixels}x${pixels}" \
        "$iconset/$filename"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$iconset" -o "$output_icns"
echo "$output_icns"
