#!/bin/bash
# Generate macOS AppIcon.appiconset from the master SVG.
# Requires librsvg (brew install librsvg) or falls back to qlmanage.
#
# Usage: ./scripts/generate-app-icon.sh

set -e

SVG_PATH="assets/app-icon.svg"
OUTPUT_DIR="Sources/ClaudeTokenManager/Resources/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SVG_PATH" ]; then
    echo "Error: $SVG_PATH not found"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Detect converter
if command -v rsvg-convert &> /dev/null; then
    CONVERTER="rsvg-convert"
    echo "→ Using rsvg-convert"
elif command -v qlmanage &> /dev/null; then
    CONVERTER="qlmanage"
    echo "→ librsvg not found, falling back to qlmanage (install librsvg for better quality: brew install librsvg)"
else
    echo "Error: no SVG converter found. Install with: brew install librsvg"
    exit 1
fi

render_png() {
    local size=$1
    local output=$2
    if [ "$CONVERTER" = "rsvg-convert" ]; then
        rsvg-convert -w "$size" -h "$size" "$SVG_PATH" -o "$output"
    else
        TMP_DIR=$(mktemp -d)
        qlmanage -t -s "$size" -o "$TMP_DIR" "$SVG_PATH" > /dev/null 2>&1
        mv "$TMP_DIR"/*.png "$output" 2>/dev/null || {
            echo "Error: qlmanage failed for size $size"
            exit 1
        }
        rm -rf "$TMP_DIR"
    fi
    echo "  ✓ $output ($size px)"
}

echo "→ Generating app icon PNGs..."
render_png 16   "$OUTPUT_DIR/icon_16x16.png"
render_png 32   "$OUTPUT_DIR/icon_16x16@2x.png"
render_png 32   "$OUTPUT_DIR/icon_32x32.png"
render_png 64   "$OUTPUT_DIR/icon_32x32@2x.png"
render_png 128  "$OUTPUT_DIR/icon_128x128.png"
render_png 256  "$OUTPUT_DIR/icon_128x128@2x.png"
render_png 256  "$OUTPUT_DIR/icon_256x256.png"
render_png 512  "$OUTPUT_DIR/icon_256x256@2x.png"
render_png 512  "$OUTPUT_DIR/icon_512x512.png"
render_png 1024 "$OUTPUT_DIR/icon_512x512@2x.png"

cat > "$OUTPUT_DIR/Contents.json" <<'EOF'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "✓ Contents.json written"
echo ""
echo "✓ App icon set generated at $OUTPUT_DIR"
echo "  Rebuild the app with ./build.sh to apply."
