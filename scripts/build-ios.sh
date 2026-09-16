#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DERIVED_DATA="${PINGBAR_DERIVED_DATA:-$ROOT/.build/ios}"

cd "$ROOT"
xcodebuild \
    -project ios/PingBarIOS.xcodeproj \
    -scheme PingBarIOS \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build

printf 'Created %s\n' "$DERIVED_DATA/Build/Products/Debug-iphoneos/PingBar.app"
