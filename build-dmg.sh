#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# 1. Build and sign the latest release bundle
echo "==> Ensuring DroidSync release bundle is up to date..."
./bundle.sh

APP_NAME="DroidSync.app"
APP_PATH="$DIR/build/$APP_NAME"
DMG_NAME="DroidSync.dmg"
DMG_PATH="$DIR/build/$DMG_NAME"
BG_IMAGE="$DIR/Resources/dmg_background.png"
VOL_ICON="$DIR/Resources/AppIcon.icns"
TEMP_DMG_SRC="$DIR/build/dmg_source"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at $APP_PATH"
    exit 1
fi

echo "==> Preparing DMG source folder..."
rm -rf "$TEMP_DMG_SRC"
mkdir -p "$TEMP_DMG_SRC"
cp -R "$APP_PATH" "$TEMP_DMG_SRC/"

# If create-dmg is installed, use it for clean UI
if command -v create-dmg &> /dev/null; then
    echo "==> Creating DMG using create-dmg with clean Finder layout..."
    rm -f "$DMG_PATH"

    create-dmg \
        --volname "DroidSync" \
        --volicon "$VOL_ICON" \
        --background "$BG_IMAGE" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 120 \
        --text-size 13 \
        --icon "$APP_NAME" 180 175 \
        --app-drop-link 480 175 \
        --hide-extension "$APP_NAME" \
        --format UDZO \
        --filesystem HFS+ \
        --overwrite \
        "$DMG_PATH" \
        "$TEMP_DMG_SRC"
else
    echo "==> create-dmg not found, creating standard DMG with hdiutil..."
    ln -s /Applications "$TEMP_DMG_SRC/Applications"
    hdiutil create -volname "DroidSync" -srcfolder "$TEMP_DMG_SRC" -ov -format UDZO "$DMG_PATH"
fi

rm -rf "$TEMP_DMG_SRC"

if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
    echo "==> Done! macOS DMG created successfully:"
    echo "    $DMG_PATH ($DMG_SIZE)"
    echo "You can test open with: open \"$DMG_PATH\""
else
    echo "Error: Failed to create DMG."
    exit 1
fi
