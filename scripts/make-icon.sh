#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
SOURCE="$PWD/assets/icon/AppIcon-source.png"
ICONSET="$PWD/assets/icon/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Sources/Assistant/Resources/AppIcon.icns
