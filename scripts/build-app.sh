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
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
# 桥接快捷指令（onboarding 一键导入用）
cp "Resources/ChargeWatch Set Battery Charge Limit.shortcut" "$RESOURCES/" 2>/dev/null || true

# 充电上限 root helper + 安装脚本（app 内首次开启时经管理员授权安装）
echo "==> swift build -c release --product chargewatch-helper"
swift build -c release --product chargewatch-helper
cp ".build/release/chargewatch-helper" "$RESOURCES/chargewatch-helper"
chmod +x "$RESOURCES/chargewatch-helper"
cp scripts/install-helper.sh "$RESOURCES/install-helper.sh"

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
