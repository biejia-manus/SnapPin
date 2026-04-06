#!/bin/bash
set -e

APP_NAME="SnapPin"

# Resolve the directory where this script lives (repo root), regardless of where it is called from
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}.app"

echo "=== Building ${APP_NAME} ==="
echo "Repo:    $BUILD_DIR"
echo "Output:  $APP_DIR"

# ── 1. Compile ────────────────────────────────────────────────────────────────
cd "$BUILD_DIR"
swift build 2>&1

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${BUILD_DIR}/.build/debug/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# ── 3. Write Info.plist ───────────────────────────────────────────────────────
cat > "${APP_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SnapPin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.snappin.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SnapPin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.1</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SnapPin needs screen recording permission to capture screenshots.</string>
</dict>
</plist>
PLIST

# ── 4. Ad-hoc code sign ───────────────────────────────────────────────────────
codesign --force --sign - "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --force --sign - "${APP_DIR}"

echo ""
echo "=== Done: ${APP_DIR} ==="
echo "Run with: open \"${APP_DIR}\""
