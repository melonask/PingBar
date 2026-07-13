#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/PingBar.iconset"
trap 'rm -rf "$WORK"' EXIT

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to regenerate the app icon." >&2
    exit 1
fi

mkdir -p "$ICONSET"
magick -background none "$ROOT/Resources/AppIcon.svg" "$WORK/background.png"
magick -background none "$ROOT/logo.svg" -resize 608x608 "$WORK/logo.png"
magick "$WORK/background.png" "$WORK/logo.png" -gravity center -composite "$WORK/icon-1024.png"

sips -z 16 16 "$WORK/icon-1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$WORK/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$WORK/icon-1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$WORK/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$WORK/icon-1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$WORK/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$WORK/icon-1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$WORK/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$WORK/icon-1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$WORK/icon-1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/PingBar.icns"
echo "Created $ROOT/Resources/PingBar.icns"
