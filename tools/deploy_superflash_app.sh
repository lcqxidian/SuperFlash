#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SuperFlash"
BUNDLE_ID="com.lcq.SuperFlash"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
APP_DIR="/Applications/${APP_NAME}.app"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

mkdir -p "$APP_DIR/Contents/Resources/scripts"
cp "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle/scripts/"*.py "$APP_DIR/Contents/Resources/scripts/"
chmod +x "$APP_DIR/Contents/Resources/scripts/"*.py

/usr/libexec/PlistBuddy -c "Clear dict" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" "$APP_DIR/Contents/Info.plist"

printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Deployed: $APP_DIR"
