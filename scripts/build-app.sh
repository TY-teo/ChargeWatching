#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_NAME="ChargeWatch"
APP_DIR="build/${BUNDLE_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/chargewatch"
if [ ! -f "$BIN" ]; then
  echo "build failed: $BIN not found" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN" "$MACOS/chargewatch"
chmod +x "$MACOS/chargewatch"
cp Resources/Info.plist "$CONTENTS/Info.plist"

# Copy SPM resource bundle if present
BUNDLE_RES=".build/release/chargewatch_ChargeWatch.bundle"
if [ -d "$BUNDLE_RES" ]; then
  cp -R "$BUNDLE_RES" "$RESOURCES/"
fi

echo "==> codesign --sign - (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

echo "==> done: $APP_DIR"
ls -la "$APP_DIR/Contents"
echo
echo "Run with: open $APP_DIR"
echo "Or install: cp -R $APP_DIR ~/Applications/"
