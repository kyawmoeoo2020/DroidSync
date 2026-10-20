#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "==> Building KMO DroidSync (Release)..."
swift build -c release

APP_NAME="KMO DroidSync.app"
APP_DIR="$DIR/build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$DIR/.build/release/KMODroidSync" "$MACOS/KMODroidSync"
cp "$DIR/Info.plist" "$CONTENTS/Info.plist"

chmod +x "$MACOS/KMODroidSync"

echo "==> Done! App bundle created at:"
echo "    $APP_DIR"
echo "You can launch it with: open \"$APP_DIR\""
