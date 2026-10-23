#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "==> Building DroidSync (Release)..."
swift build -c release

APP_NAME="DroidSync.app"
APP_DIR="$DIR/build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating macOS App Bundle at $APP_DIR..."
# Remove any old builds
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$DIR/.build/release/DroidSync" "$MACOS/DroidSync"
cp "$DIR/Info.plist" "$CONTENTS/Info.plist"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

if [ -f "$DIR/Resources/DroidSync_Logo.png" ]; then
    cp "$DIR/Resources/DroidSync_Logo.png" "$RESOURCES/DroidSync_Logo.png"
fi

# Copy SPM resource bundle if present (for Bundle.module support)
if [ -d "$DIR/.build/release/DroidSync_DroidSync.bundle" ]; then
    cp -R "$DIR/.build/release/DroidSync_DroidSync.bundle" "$RESOURCES/"
fi

chmod +x "$MACOS/DroidSync"

echo "==> Signing App Bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done! App bundle created at:"
echo "    $APP_DIR"
echo "You can launch it with: open \"$APP_DIR\""
