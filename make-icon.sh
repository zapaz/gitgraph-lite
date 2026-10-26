#!/bin/zsh
set -eu
ROOT="${0:A:h}"
WORK="${GITGRAPH_BUILD_ROOT:-${ROOT}/.build-local}"
ICONSET="${WORK}/icons/AppIcon.iconset"
mkdir -p "$ICONSET"
for iconsize in 16 32 128 256 512; do
    sips -z "$iconsize" "$iconsize" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${iconsize}x${iconsize}.png" >/dev/null
    retina=$((iconsize * 2))
    sips -z "$retina" "$retina" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${iconsize}x${iconsize}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Assets/AppIcon.icns"
