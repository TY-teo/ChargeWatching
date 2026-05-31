#!/bin/bash
# ChargeWatch 充电上限 root helper 安装/卸载（本地个人用，ad-hoc 签名 + 手动 LaunchDaemon）。
# 用法：
#   bash scripts/install-helper.sh install [helper二进制路径]   # 安装并启动（需 root）
#   bash scripts/install-helper.sh uninstall                    # 停止并移除（恢复充电）
# 由 app 经 osascript "with administrator privileges" 调用（首次开启时弹一次密码）。
set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

LABEL="com.chenran.chargewatch.helper"
HELPER="/Library/PrivilegedHelperTools/${LABEL}"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DEFAULT_BIN="$(pwd)/.build/release/chargewatch-helper"
BIN="${2:-$DEFAULT_BIN}"
CFGDIR="/Users/Shared/ChargeWatch"
LOG="/var/log/chargewatch-helper.log"

[ "$(id -u)" -eq 0 ] || { echo "ERR 需 root"; exit 10; }

uninstall() {
  echo "==> bootout $LABEL"
  launchctl bootout "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
  sleep 1
  rm -f "$HELPER" "$PLIST"
  echo "==> 已移除（充电恢复）"
}

install() {
  [ -f "$BIN" ] || { echo "ERR 未找到 helper 二进制: $BIN"; exit 11; }
  echo "==> 源 helper: $BIN"
  launchctl bootout "system/${LABEL}" 2>/dev/null || true
  sleep 1

  echo "==> 安装到 $HELPER"
  mkdir -p /Library/PrivilegedHelperTools || { echo "ERR mkdir helpertools"; exit 12; }
  cp "$BIN" "$HELPER" || { echo "ERR cp helper"; exit 13; }
  chown root:wheel "$HELPER"; chmod 544 "$HELPER"
  xattr -dr com.apple.quarantine "$HELPER" 2>/dev/null || true
  codesign --force --sign - "$HELPER" 2>&1 | sed 's/^/    codesign: /' || true

  echo "==> 写 $PLIST"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>Program</key><string>${HELPER}</string>
  <key>ProgramArguments</key><array><string>${HELPER}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
  <key>StandardOutPath</key><string>${LOG}</string>
</dict></plist>
PLISTEOF
  chown root:wheel "$PLIST"; chmod 644 "$PLIST"

  echo "==> 配置目录 $CFGDIR"
  mkdir -p "$CFGDIR"; chmod 777 "$CFGDIR"
  [ -f "$CFGDIR/smc-limit.json" ] || echo '{"enabled":false,"limit":80,"deadband":3}' > "$CFGDIR/smc-limit.json"
  chmod 666 "$CFGDIR/smc-limit.json"

  echo "==> bootstrap"
  BOOT_OUT="$(launchctl bootstrap system "$PLIST" 2>&1)"; BOOT_RC=$?
  echo "    bootstrap rc=$BOOT_RC out=[$BOOT_OUT]"
  if [ $BOOT_RC -ne 0 ]; then
    echo "==> bootstrap 非零，尝试 enable + kickstart"
    launchctl enable "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
    launchctl kickstart -k "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
  fi
  sleep 1
  if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    echo "==> OK 守护进程已注册:"
    launchctl print "system/${LABEL}" 2>/dev/null | grep -E "state =|pid =" | sed 's/^/    /'
    echo "DONE-OK"
  else
    echo "ERR 守护进程未注册（见上方 bootstrap 输出）"; exit 14
  fi
}

case "${1:-install}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "用法: install|uninstall"; exit 1 ;;
esac
