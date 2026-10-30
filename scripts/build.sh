#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PROJECT_DIR/build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --scratch-path "$PROJECT_DIR/build/swift" -c "$CONFIGURATION"
BIN_DIR="$(swift build --disable-sandbox --scratch-path "$PROJECT_DIR/build/swift" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/Album Artwork.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/AlbumArtwork" "$APP_DIR/Contents/MacOS/AlbumArtwork"
cp "$PROJECT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
ditto "$PROJECT_DIR/Sources/AlbumArtwork/Scripts" "$APP_DIR/Contents/Resources/Scripts"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --options runtime \
    --entitlements "$PROJECT_DIR/Support/AlbumArtwork.entitlements" \
    --identifier com.local.AlbumArtwork "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf '\nBuilt: %s\n' "$APP_DIR"
