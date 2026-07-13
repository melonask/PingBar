#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/PingBar.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
xcrun swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/PingBar" "$CONTENTS/MacOS/PingBar"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/PingBar.icns" "$CONTENTS/Resources/PingBar.icns"
codesign --force --sign - "$APP"

printf 'Created %s\n' "$APP"
