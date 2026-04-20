#!/bin/bash
set -e

# Build a distributable .app bundle for Claude Token Manager
# Usage: ./build.sh [release|debug]

CONFIG="${1:-release}"
APP_NAME="Claude Token Manager"
BUNDLE_ID="com.lucas.claude-token-manager"
EXECUTABLE="ClaudeTokenManager"

echo "→ Building Swift package ($CONFIG)..."
if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BUILD_PATH=".build/release/$EXECUTABLE"
else
    swift build
    BUILD_PATH=".build/debug/$EXECUTABLE"
fi

echo "→ Assembling .app bundle..."
APP_BUNDLE="build/$APP_NAME.app"
rm -rf "build"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Generate .icns from appiconset PNGs
ICONSET_DIR="Sources/ClaudeTokenManager/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_DIR" ] && [ -f "$ICONSET_DIR/icon_512x512@2x.png" ]; then
    ICONSET_TMP=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_TMP"
    cp "$ICONSET_DIR/icon_16x16.png" "$ICONSET_TMP/icon_16x16.png"
    cp "$ICONSET_DIR/icon_16x16@2x.png" "$ICONSET_TMP/icon_16x16@2x.png"
    cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_TMP/icon_32x32.png"
    cp "$ICONSET_DIR/icon_32x32@2x.png" "$ICONSET_TMP/icon_32x32@2x.png"
    cp "$ICONSET_DIR/icon_128x128.png" "$ICONSET_TMP/icon_128x128.png"
    cp "$ICONSET_DIR/icon_128x128@2x.png" "$ICONSET_TMP/icon_128x128@2x.png"
    cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_TMP/icon_256x256.png"
    cp "$ICONSET_DIR/icon_256x256@2x.png" "$ICONSET_TMP/icon_256x256@2x.png"
    cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_TMP/icon_512x512.png"
    cp "$ICONSET_DIR/icon_512x512@2x.png" "$ICONSET_TMP/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_TMP" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_TMP")"
    echo "  ✓ AppIcon.icns generated"
elif [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

echo "→ Ad-hoc signing (for local use)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✓ Done: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  mv \"$APP_BUNDLE\" /Applications/"
echo "  open \"/Applications/$APP_NAME.app\""
echo ""
echo "To distribute to others, you'll need to:"
echo "  1. Sign with a Developer ID certificate"
echo "  2. Notarize with Apple"
echo "  See README.md for details."
