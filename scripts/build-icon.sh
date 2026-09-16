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

# iOS icons must be full-bleed opaque squares: the system applies its own
# rounding, so the macOS background's padding and rounded corners are dropped
# in favour of the icon's green face edge to edge.
APPICON="$ROOT/ios/PingBarIOS/Assets.xcassets/AppIcon.appiconset"
IOS_SIZE=1024
magick -background none "$ROOT/logo.svg" -resize 660x660 "$WORK/logo-ios.png"
magick -size "$IOS_SIZE"x"$IOS_SIZE" xc:'#30d158' "$WORK/logo-ios.png" \
    -gravity center -composite -alpha remove -alpha off "$WORK/icon-ios.png"

mkdir -p "$APPICON"
sips -z "$IOS_SIZE" "$IOS_SIZE" "$WORK/icon-ios.png" --out "$APPICON/Icon-1024.png" >/dev/null
sips -z 40 40 "$WORK/icon-ios.png" --out "$APPICON/Icon-20@2x.png" >/dev/null
sips -z 60 60 "$WORK/icon-ios.png" --out "$APPICON/Icon-20@3x.png" >/dev/null
sips -z 58 58 "$WORK/icon-ios.png" --out "$APPICON/Icon-29@2x.png" >/dev/null
sips -z 87 87 "$WORK/icon-ios.png" --out "$APPICON/Icon-29@3x.png" >/dev/null
sips -z 80 80 "$WORK/icon-ios.png" --out "$APPICON/Icon-40@2x.png" >/dev/null
sips -z 120 120 "$WORK/icon-ios.png" --out "$APPICON/Icon-40@3x.png" >/dev/null
sips -z 120 120 "$WORK/icon-ios.png" --out "$APPICON/Icon-60@2x.png" >/dev/null
sips -z 180 180 "$WORK/icon-ios.png" --out "$APPICON/Icon-60@3x.png" >/dev/null

echo "Created $APPICON"
