#!/usr/bin/env bash
# gracerlte VoLTE — adb installer (Linux / macOS)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-adb}"

die()  { echo "[volte][错误] $*" >&2; exit 1; }
info() { echo "[volte] $*"; }

command -v "$ADB" >/dev/null 2>&1 || die "找不到 adb（可设置 ADB=/path/to/adb）"

info "检查设备..."
"$ADB" devices | awk 'NR>1 && $2=="device" {found=1} END {exit !found}' \
    || die "未检测到已授权设备"

info "获取 root..."
"$ADB" root >/dev/null 2>&1 || true
sleep 2
"$ADB" wait-for-device
"$ADB" shell id | grep -q "uid=0" || die "adb root 失败（需要 userdebug 系统）"

info "推送文件..."
"$ADB" shell "mkdir -p /data/local/tmp/volte" >/dev/null
"$ADB" push "$ROOT/prebuilt/PhhIms-50.apk"                 "/data/local/tmp/volte/PhhIms.apk" >/dev/null
"$ADB" push "$ROOT/prebuilt/PhhImsOverlay-50.apk"          "/data/local/tmp/volte/PhhImsOverlay.apk" >/dev/null
"$ADB" push "$ROOT/src/android.hardware.telephony.ims.xml" "/data/local/tmp/volte/ims-feature.xml" >/dev/null
"$ADB" push "$ROOT/src/privapp-permissions-me.phh.ims.xml" "/data/local/tmp/volte/privapp.xml" >/dev/null
"$ADB" push "$ROOT/tools/device-install.sh"                "/data/local/tmp/volte/install.sh" >/dev/null

info "执行安装..."
"$ADB" shell "sh /data/local/tmp/volte/install.sh" || die "安装脚本失败"

info "重启..."
"$ADB" reboot >/dev/null
sleep 5
"$ADB" wait-for-device

info "等待开机..."
for _ in $(seq 1 60); do
    sleep 5
    [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
done

sleep 20
info "验证："
"$ADB" shell 'dumpsys package me.phh.ims | grep versionCode; cmd overlay list | grep me.phh.ims.overlay; getprop persist.dbg.volte_avail_ovr; logcat -b all -d | grep -E "IMS registration ready|REGISTERED" | tail -2'

echo
echo "[volte] 完成。出现 REGISTER 200 OK / REGISTERED 即可拨测。"
