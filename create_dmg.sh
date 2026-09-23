#!/bin/bash
set -euo pipefail

APP_NAME="SnapPin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP_NAME}.app"
DMG_DIR="${DMG_OUTPUT_DIR:-$SCRIPT_DIR}"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found. Run build_app.sh first." >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
DMG_NAME="${DMG_NAME:-${APP_NAME}-${VERSION}.dmg}"
mkdir -p "$DMG_DIR"
DMG_DIR="$(cd "$DMG_DIR" && pwd)"
DMG_PATH="${DMG_DIR}/${DMG_NAME}"
if [ -e "$DMG_PATH" ]; then
    echo "Error: ${DMG_PATH} already exists; move it aside before rebuilding." >&2
    exit 1
fi

# A unique staging folder avoids collisions with other builds.
DMG_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
trap 'rm -rf "$DMG_TEMP"' EXIT

echo "=== Creating DMG for ${APP_NAME} v${VERSION} ==="
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
ditto "$APP_PATH" "${DMG_TEMP}/${APP_NAME}.app"
ln -s /Applications "${DMG_TEMP}/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "=== DMG created successfully ==="
ls -lh "$DMG_PATH"
