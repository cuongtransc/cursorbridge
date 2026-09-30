#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/CursorBridge.app"

swift build -c "$CONFIGURATION" --product CursorBridge ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"})"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CursorBridge" "$APP/Contents/MacOS/CursorBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Accessibility grants are checked against the app's designated requirement. An ad-hoc signature's
# default requirement is its cdhash, which changes on every build and silently invalidates the grant,
# so ad-hoc builds pin the requirement to the bundle identifier instead.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
    codesign --force --options runtime --sign - \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
else
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
fi

echo "Built $APP"
