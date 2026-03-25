#!/bin/bash
set -e

APP_NAME="SnapPin"
BUILD_DIR="/Users/beejah/Documents/SnapPin"
APP_DIR="/Users/beejah/Documents/SnapPin.app"

rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${BUILD_DIR}/.build/debug/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>SnapPin</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.snappin.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>SnapPin</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>SnapPin needs screen recording permission to capture screenshots.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --force --sign - "${APP_DIR}"

echo "Done: ${APP_DIR}"
