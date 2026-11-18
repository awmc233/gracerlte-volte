#!/usr/bin/env bash
# gracerlte VoLTE — 安装后验证脚本（Linux / macOS / WSL）
#
# 用法:
#   ./tools/verify.sh              # 用默认 adb、默认设备
#   ADB=/path/to/adb ./tools/verify.sh
#   ./tools/verify.sh -s <serial>  # 指定设备
#
# 退出码: 0 = 全部通过；1 = 有关键项失败；2 = 用法错误
set -uo pipefail

ADB_BIN="${ADB:-adb}"
SERIAL=""

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -s)
            [ $# -ge 2 ] || { echo "缺少 -s 的参数" >&2; exit 2; }
            SERIAL="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

adb() {
    if [ -n "$SERIAL" ]; then
        "$ADB_BIN" -s "$SERIAL" "$@"
    else
        "$ADB_BIN" "$@"
    fi
}

PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS + 1)); printf '  \033[32m[ OK ]\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; }
warn() { WARN=$((WARN + 1)); printf '  \033[33m[WARN]\033[0m %s\n' "$1"; }
info() { printf '  ..      %s\n' "$1"; }

trim() { tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

echo "== gracerlte VoLTE 验证 =="

# 0. adb 可用、设备在线
command -v "$ADB_BIN" >/dev/null 2>&1 || { echo "找不到 adb（可用 ADB=/path/to/adb 指定）" >&2; exit 1; }
state=$(adb get-state 2>/dev/null | trim || true)
if [ "$state" = "device" ]; then
    ok "设备在线 ($(adb shell getprop ro.product.device 2>/dev/null | trim))"
else
    bad "设备不在线（adb get-state = ${state:-无响应}）"
    echo
    echo "结果: $PASS 通过 / $FAIL 失败 / $WARN 警告"
    exit 1
fi

# 1. APK 版本
ver=$(adb shell dumpsys package me.phh.ims 2>/dev/null | grep -m1 'versionCode=' | trim || true)
case "$ver" in
    *versionCode=50*) ok "PhhIms 已安装，versionCode=50" ;;
    "")               bad "查不到 me.phh.ims（未安装？）" ;;
    *)                bad "版本不符: $ver（期望 50）" ;;
esac

# 2. RRO overlay
if adb shell cmd overlay list 2>/dev/null | grep -q '\[x\].*me\.phh\.ims\.overlay'; then
    ok "overlay 已启用"
else
    bad "overlay me.phh.ims.overlay 未启用"
fi

# 3. VoLTE 开关属性
volte=$(adb shell getprop persist.dbg.volte_avail_ovr 2>/dev/null | trim)
if [ "$volte" = "1" ]; then
    ok "persist.dbg.volte_avail_ovr = 1"
else
    bad "persist.dbg.volte_avail_ovr = ${volte:-空}（期望 1）"
fi

# 4. IMS 特性声明
if adb shell pm list features 2>/dev/null | grep -q 'android.hardware.telephony.ims'; then
    ok "IMS 特性已声明"
else
    bad "缺少 android.hardware.telephony.ims 特性"
fi

# 5. IMS 注册日志
reg=$(adb logcat -b all -d 2>/dev/null | grep -E 'IMS registration ready|REGISTRATION_STATE_REGISTERED' | tail -n 2 || true)
if [ -n "$reg" ]; then
    ok "日志里有 IMS 注册成功记录"
    printf '%s\n' "$reg" | sed 's/^/          /'
else
    warn "日志里没找到注册成功记录（可能刚重启、尚未注册）"
fi

# 6. IMS PDN
if adb shell dumpsys connectivity 2>/dev/null | grep -q 'extra: ims'; then
    ok "IMS PDN 已建立"
else
    warn "dumpsys connectivity 里没看到 extra: ims"
fi

# 7. 当前注册状态
st=$(adb shell dumpsys telephony.registry 2>/dev/null | grep -m1 'mImsRegistrationState' | trim || true)
[ -n "$st" ] && info "注册状态: $st"

echo
printf '结果: %d 通过 / %d 失败 / %d 警告\n' "$PASS" "$FAIL" "$WARN"
if [ "$FAIL" -eq 0 ]; then
    echo "基础检查通过。请再拨测一通去电与来电，确认双向音频。"
    exit 0
fi
echo "有检查未通过，请按提示排查（见 README / docs/IMS-VoLTE-诊断报告.md）。" >&2
exit 1
