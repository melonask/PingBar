#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/PingBar.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
xcrun swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp "$ROOT/.build/release/PingBar" "$CONTENTS/MacOS/PingBar"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
codesign --force --sign - "$APP"

printf 'Created %s\n' "$APP"
