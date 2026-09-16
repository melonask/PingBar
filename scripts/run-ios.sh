#!/bin/sh
set -eu

# Builds, installs, and launches PingBar on a connected iPhone.
# Usage: ./scripts/run-ios.sh [device-name]   (default: partyPhone)

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEVICE="${1:-partyPhone}"
BUNDLE_ID="com.local.PingBarIOS"
DERIVED_DATA="${PINGBAR_DERIVED_DATA:-$ROOT/.build/ios}"

cd "$ROOT"

UDID="$(xcrun devicectl list devices 2>/dev/null \
    | awk -v name="$DEVICE" '$1 == name && /physical/ { print $2; exit }')"

if [ -z "$UDID" ]; then
    printf 'No connected device named "%s".\n\n' "$DEVICE" >&2
    xcrun devicectl list devices >&2
    exit 1
fi

xcodebuild \
    -project ios/PingBarIOS.xcodeproj \
    -scheme PingBarIOS \
    -configuration Debug \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build

xcrun devicectl device install app \
    --device "$UDID" \
    "$DERIVED_DATA/Build/Products/Debug-iphoneos/PingBar.app"

xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"

printf 'Running PingBar on %s (%s)\n' "$DEVICE" "$UDID"
