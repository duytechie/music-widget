#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PROJECT_DIR/build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
# UNIVERSAL=1 builds a fat arm64 + x86_64 binary (used by release.sh).
SCRATCH_PATH="$PROJECT_DIR/build/swift"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    SCRATCH_PATH="$PROJECT_DIR/build/universal"
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build --disable-sandbox --scratch-path "$SCRATCH_PATH" -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build --disable-sandbox --scratch-path "$SCRATCH_PATH" -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/Album Artwork.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/AlbumArtwork" "$APP_DIR/Contents/MacOS/AlbumArtwork"
cp "$PROJECT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Support/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Support/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
ditto "$PROJECT_DIR/Sources/AlbumArtwork/Scripts" "$APP_DIR/Contents/Resources/Scripts"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --options runtime \
    --entitlements "$PROJECT_DIR/Support/AlbumArtwork.entitlements" \
    --identifier com.local.AlbumArtwork "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf '\nBuilt: %s\n' "$APP_DIR"
