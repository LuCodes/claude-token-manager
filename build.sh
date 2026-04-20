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

# Optional icon — drop AppIcon.icns in the repo root to include it
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
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
