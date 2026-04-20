#!/bin/bash
set -e

SVG="assets/menu-bar-icon.svg"
OUT_DIR="Sources/ClaudeTokenManager/Resources/Assets.xcassets/MenuBarIcon.imageset"

if [ ! -f "$SVG" ]; then
    echo "Error: $SVG not found"
    exit 1
fi

mkdir -p "$OUT_DIR"

if command -v rsvg-convert &> /dev/null; then
    rsvg-convert -f pdf "$SVG" -o "$OUT_DIR/MenuBarIcon.pdf"
    echo "✓ PDF generated"
else
    echo "rsvg-convert not found, using PNG fallback"
    rsvg-convert -w 64 "$SVG" -o "$OUT_DIR/MenuBarIcon.png" 2>/dev/null || \
    qlmanage -t -s 64 -o /tmp "$SVG" > /dev/null 2>&1 && mv /tmp/menu-bar-icon.svg.png "$OUT_DIR/MenuBarIcon.png"
    rsvg-convert -w 128 "$SVG" -o "$OUT_DIR/MenuBarIcon@2x.png" 2>/dev/null || \
    qlmanage -t -s 128 -o /tmp "$SVG" > /dev/null 2>&1 && mv /tmp/menu-bar-icon.svg.png "$OUT_DIR/MenuBarIcon@2x.png"
fi

echo "✓ Menu bar icon updated in $OUT_DIR"
echo "  Rebuild with ./build.sh to apply."
