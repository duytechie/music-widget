#!/bin/bash
# Regenerates the app icon from docs/app-icon.svg.
#
# macOS 26 restyles legacy .icns icons with an automatic Liquid Glass effect,
# which lightens the note and adds bevels. To keep the design's exact colors we
# build an Icon Composer bundle (Support/AppIcon.icon) with glass, specular and
# shadow turned off, then compile it with actool into:
#   Support/Assets.car   - used on macOS 26+ (CFBundleIconName)
#   Support/AppIcon.icns - fallback for older macOS (CFBundleIconFile)
# Requires Xcode 26+ (actool).
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$PROJECT_DIR/docs/app-icon.svg"
ICON="$PROJECT_DIR/Support/AppIcon.icon"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Background color comes from the SVG's Background rect.
BG_HEX="$(sed -n 's/.*id="Background".*fill="#\([0-9A-Fa-f]\{6\}\)".*/\1/p' "$SVG")"
[ -n "$BG_HEX" ] || { echo "Background fill not found in $SVG" >&2; exit 1; }
BG="$(python3 -I -c "h='$BG_HEX'; print(','.join(f'{int(h[i:i+2],16)/255:.5f}' for i in (0,2,4)))")"

rm -rf "$ICON"
mkdir -p "$ICON/Assets"
# Foreground layer: the design without its background rect.
grep -v 'id="Background"' "$SVG" > "$ICON/Assets/note.svg"
cat > "$ICON/icon.json" <<JSON
{
  "fill" : { "solid" : "srgb:$BG,1.00000" },
  "groups" : [
    {
      "layers" : [ { "glass" : false, "image-name" : "note.svg", "name" : "note" } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON

xcrun actool "$ICON" --compile "$WORK" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$WORK/partial.plist" >/dev/null
cp "$WORK/Assets.car" "$PROJECT_DIR/Support/Assets.car"
cp "$WORK/AppIcon.icns" "$PROJECT_DIR/Support/AppIcon.icns"
echo "Wrote Support/AppIcon.icon, Support/Assets.car, Support/AppIcon.icns"
