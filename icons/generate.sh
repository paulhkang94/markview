#!/usr/bin/env bash
# Generate MarkView app icons for all platforms from icons/markview-icon.svg
#
# Requires: cairosvg (pip3 install cairosvg), iconutil (macOS built-in)
# Usage: bash icons/generate.sh [--all | --macos | --ios | --android]
#
# Output:
#   macOS  → Sources/MarkView/Resources/AppIcon.icns
#   iOS    → markview-ios repo (../markview-ios/Assets.xcassets/…)
#   Android → markview-android repo (../markview-android/app/src/main/res/drawable/…)
#             Note: Android uses XML vector drawables derived from the SVG path.
#             Run this script to regenerate macOS + iOS PNGs. Android AVDs must
#             be updated manually when the path changes (see icons/README.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SVG="$SCRIPT_DIR/markview-icon.svg"
TMP="$(mktemp -d)"

TARGET="${1:---all}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1 (install with: $2)"; }

need python3 "brew install python3"
python3 -c "import cairosvg" 2>/dev/null || die "cairosvg not installed (pip3 install cairosvg)"
need iconutil "built-in on macOS"
need sips     "built-in on macOS"

echo "=== MarkView Icon Generator ==="
echo "Source: $SVG"
echo ""

# ── Rasterize SVG → PNGs ────────────────────────────────────────────────────
echo "Rasterizing..."
python3 - "$SVG" "$TMP" << 'PYEOF'
import sys, cairosvg, os
svg, out = sys.argv[1], sys.argv[2]
for size in [16, 32, 64, 128, 256, 512, 1024]:
    cairosvg.svg2png(url=svg, write_to=f"{out}/icon_{size}.png",
                     output_width=size, output_height=size)
    print(f"  {size}×{size}")
PYEOF

# ── macOS ────────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "--all" || "$TARGET" == "--macos" ]]; then
    echo ""
    echo "macOS → AppIcon.icns"
    ICONSET="$TMP/MarkView.iconset"
    mkdir -p "$ICONSET"
    cp "$TMP/icon_16.png"   "$ICONSET/icon_16x16.png"
    cp "$TMP/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$TMP/icon_32.png"   "$ICONSET/icon_32x32.png"
    cp "$TMP/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$TMP/icon_128.png"  "$ICONSET/icon_128x128.png"
    cp "$TMP/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
    cp "$TMP/icon_256.png"  "$ICONSET/icon_256x256.png"
    cp "$TMP/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
    cp "$TMP/icon_512.png"  "$ICONSET/icon_512x512.png"
    cp "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
    iconutil --convert icns "$ICONSET" \
        --output "$REPO_ROOT/Sources/MarkView/Resources/AppIcon.icns"
    echo "  ✓ Sources/MarkView/Resources/AppIcon.icns"
fi

# ── iOS ──────────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "--all" || "$TARGET" == "--ios" ]]; then
    echo ""
    echo "iOS → Assets.xcassets"
    IOS_XCASSETS="$REPO_ROOT/../markview-ios/Assets.xcassets/AppIcon.appiconset"
    [[ -d "$IOS_XCASSETS" ]] || die "markview-ios not found at $REPO_ROOT/../markview-ios"
    SRC="$TMP/icon_1024.png"
    declare -A SIZES=(
        ["20"]="Icon-20" ["40"]="Icon-20@2x" ["60"]="Icon-20@3x"
        ["29"]="Icon-29" ["58"]="Icon-29@2x" ["87"]="Icon-29@3x"
        ["40"]="Icon-40" ["80"]="Icon-40@2x" ["120"]="Icon-40@3x"
        ["120"]="Icon-60@2x" ["180"]="Icon-60@3x"
        ["76"]="Icon-76"  ["152"]="Icon-76@2x" ["167"]="Icon-83.5@2x"
    )
    # Use ordered list to avoid duplicate-key collision in bash associative array
    while IFS=',' read -r px label; do
        sips -z "$px" "$px" "$SRC" --out "$IOS_XCASSETS/${label}.png" 2>/dev/null
    done << 'SIZES'
20,Icon-20
40,Icon-20@2x
60,Icon-20@3x
29,Icon-29
58,Icon-29@2x
87,Icon-29@3x
40,Icon-40
80,Icon-40@2x
120,Icon-40@3x
120,Icon-60@2x
180,Icon-60@3x
76,Icon-76
152,Icon-76@2x
167,Icon-83.5@2x
SIZES
    cp "$SRC" "$IOS_XCASSETS/Icon-1024.png"
    echo "  ✓ $(ls "$IOS_XCASSETS"/*.png | wc -l | tr -d ' ') PNGs in Assets.xcassets"
fi

# ── Android ──────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "--all" || "$TARGET" == "--android" ]]; then
    echo ""
    echo "Android → note"
    echo "  Android adaptive icons use XML vector drawables (AVD format), not PNGs."
    echo "  The M path in ic_launcher_foreground.xml is pre-scaled from markview-icon.svg."
    echo "  If you change the SVG path, update the Android AVD path manually:"
    echo "    scale factor = 108/1024 = 0.10547"
    echo "    file: markview-android/app/src/main/res/drawable/ic_launcher_foreground.xml"
fi

rm -rf "$TMP"

# ── README previews (always regenerate so icons/README.md stays in sync) ─────
echo ""
echo "Regenerating README previews..."
python3 - "$SVG" "$SCRIPT_DIR/previews" << 'PYEOF'
import sys, cairosvg, os, io
from PIL import Image, ImageDraw

svg, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
SIZE = 256

raw = cairosvg.svg2png(url=svg, output_width=SIZE*4, output_height=SIZE*4)
src = Image.open(io.BytesIO(raw)).convert("RGBA").resize((SIZE,SIZE), Image.LANCZOS)

def masked(img, mask):
    result = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
    icon = img.copy(); icon.putalpha(mask)
    result.paste(icon, mask=icon.split()[3])
    return result

def rrect(r=0.225):
    m = Image.new("L",(SIZE,SIZE),0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,SIZE-1,SIZE-1],radius=int(SIZE*r),fill=255)
    return m

def circle():
    m = Image.new("L",(SIZE,SIZE),0)
    ImageDraw.Draw(m).ellipse([0,0,SIZE-1,SIZE-1],fill=255)
    return m

src.save(f"{out}/flat.png")
masked(src, rrect()).save(f"{out}/macos.png")
masked(src, rrect()).save(f"{out}/ios.png")
masked(src, circle()).save(f"{out}/android.png")

# Size strip
sizes = [16, 32, 64, 128, 256]
W = sum(sizes) + 8*(len(sizes)-1)
strip = Image.new("RGBA", (W, 256), (0,0,0,0))
x = 0
for s in sizes:
    tile_raw = cairosvg.svg2png(url=svg, output_width=s*4, output_height=s*4)
    tile = Image.open(io.BytesIO(tile_raw)).resize((s,s), Image.LANCZOS)
    strip.paste(tile, (x, 256-s))
    x += s + 8
strip.save(f"{out}/sizes.png")
print(f"  ✓ previews/flat.png, macos.png, ios.png, android.png, sizes.png")
PYEOF

echo ""
echo "=== Done ==="
echo "Next: bash scripts/bundle.sh --install (macOS), xcodegen + xcodebuild (iOS),"
echo "      gradlew assembleDebug + adb install (Android)"
