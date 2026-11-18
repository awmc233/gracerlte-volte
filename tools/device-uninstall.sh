#!/system/bin/sh
# gracerlte VoLTE — on-device uninstaller (run as root via adb)
[ "$(id -u)" = "0" ] || { echo "[volte][ERROR] 需要 root"; exit 1; }

mount -o remount,rw / 2>/dev/null || mount -o rw,remount / 2>/dev/null

rm -f /system/etc/permissions/android.hardware.telephony.ims.xml
rm -f /system/etc/permissions/privapp-permissions-phh.xml
rm -rf /system/priv-app/PhhIms
rm -f /system/product/overlay/PhhImsOverlay.apk

setprop persist.dbg.volte_avail_ovr 0
setprop persist.dbg.wfc_avail_ovr 0
setprop persist.dbg.allow_ims_off 0
setprop persist.radio.calls.on.ims 0
settings put global enhanced_4g_mode_enabled 0

rm -rf /data/system/package_cache/* 2>/dev/null
sync
echo "[volte] 已卸载，重启后恢复原状。"
