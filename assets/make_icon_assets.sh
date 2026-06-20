#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
SVG="$ASSETS_DIR/AppIcon.svg"
ICONSET="$ASSETS_DIR/AppIcon.iconset"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

magick -background none "$SVG" -resize 16x16 "$ICONSET/icon_16x16.png"
magick -background none "$SVG" -resize 32x32 "$ICONSET/icon_16x16@2x.png"
magick -background none "$SVG" -resize 32x32 "$ICONSET/icon_32x32.png"
magick -background none "$SVG" -resize 64x64 "$ICONSET/icon_32x32@2x.png"
magick -background none "$SVG" -resize 128x128 "$ICONSET/icon_128x128.png"
magick -background none "$SVG" -resize 256x256 "$ICONSET/icon_128x128@2x.png"
magick -background none "$SVG" -resize 256x256 "$ICONSET/icon_256x256.png"
magick -background none "$SVG" -resize 512x512 "$ICONSET/icon_256x256@2x.png"
magick -background none "$SVG" -resize 512x512 "$ICONSET/icon_512x512.png"
magick -background none "$SVG" -resize 1024x1024 "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ASSETS_DIR/AppIcon.icns"

magick -background none "$SVG" \
  -define icon:auto-resize=256,128,64,48,32,24,16 \
  "$ASSETS_DIR/AppIcon.ico"

echo "Built icon assets in $ASSETS_DIR"
