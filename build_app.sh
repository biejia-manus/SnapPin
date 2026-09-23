#!/bin/bash
set -euo pipefail

APP_NAME="SnapPin"
CONFIGURATION="${CONFIGURATION:-debug}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Error: CONFIGURATION must be debug or release." >&2; exit 1 ;;
esac

# Resolve paths from the repository, not the caller's current directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}.app"
INFO_PLIST="${SCRIPT_DIR}/SnapPin/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

echo "=== Building ${APP_NAME} ${VERSION} (${CONFIGURATION}) ==="
echo "Repo:    $SCRIPT_DIR"
echo "Output:  $APP_DIR"

# 1. Compile and ask SwiftPM for its actual output directory.
cd "$SCRIPT_DIR"
swift build --configuration "$CONFIGURATION" 2>&1
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

# 2. Assemble the app bundle using a single source of version metadata.
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${SCRIPT_DIR}/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST" "${APP_DIR}/Contents/Info.plist"
plutil -lint "${APP_DIR}/Contents/Info.plist"

# 3. Ad-hoc sign. This is not Developer ID signing or Apple notarization.
codesign --force --sign - "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo ""
echo "=== Done: ${APP_DIR} ==="
echo "Run with: open \"${APP_DIR}\""
