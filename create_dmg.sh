#!/bin/bash
set -e

APP_NAME="SnapPin"
VERSION="1.0.3"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# Resolve paths relative to this script (repo root)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP_NAME}.app"
DMG_DIR="${SCRIPT_DIR}"
DMG_TEMP="${DMG_DIR}/.dmg_tmp"

echo "=== Creating DMG for ${APP_NAME} v${VERSION} ==="
echo "App:  $APP_PATH"
echo "DMG:  ${DMG_DIR}/${DMG_NAME}"

# ── 1. Verify .app exists ─────────────────────────────────────────────────────
if [ ! -d "$APP_PATH" ]; then
    echo ""
    echo "Error: ${APP_PATH} not found."
    echo "Run build_app.sh first to build the app bundle."
    exit 1
fi

# ── 2. Prepare temp staging folder ───────────────────────────────────────────
rm -rf "$DMG_TEMP" "${DMG_DIR}/${DMG_NAME}"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "${DMG_TEMP}/Applications"

# ── 3. Create compressed DMG ─────────────────────────────────────────────────
echo "Packing DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "${DMG_DIR}/${DMG_NAME}"

# ── 4. Clean up ───────────────────────────────────────────────────────────────
rm -rf "$DMG_TEMP"

echo ""
echo "=== DMG created successfully ==="
echo "Location: ${DMG_DIR}/${DMG_NAME}"
ls -lh "${DMG_DIR}/${DMG_NAME}"
