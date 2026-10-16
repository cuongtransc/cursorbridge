#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
source scripts/signing.sh

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/CursorBridge.app"

swift build -c "$CONFIGURATION" --product CursorBridge ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"})"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CursorBridge" "$APP/Contents/MacOS/CursorBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The icon is drawn by the app's own code (AppIcon.swift), so it is rendered here rather than committed.
ICONSET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
"$BIN_DIR/CursorBridge" --write-iconset "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

# Accessibility grants are checked against the app's designated requirement. A certificate-signed build's
# requirement names the certificate, so the grant survives rebuilds. An ad-hoc build's is its cdhash, which
# changes on every build; it is kept that way because a requirement of the bundle identifier alone would
# let any ad-hoc binary claiming that identifier inherit the grant.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning | grep -qF "\"$LOCAL_IDENTITY\""; then
    IDENTITY="$LOCAL_IDENTITY"
fi
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    echo "warning: ad-hoc signing; Accessibility must be granted again after each build (fix: mise run setup)" >&2
    IDENTITY="-"
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signed: $IDENTITY)"
