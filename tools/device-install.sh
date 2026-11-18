#!/system/bin/sh
# gracerlte VoLTE — on-device installer (run as root via adb)
BASE=/data/local/tmp/volte

log()  { echo "[volte] $*"; }
fail() { echo "[volte][ERROR] $*"; exit 1; }

[ "$(id -u)" = "0" ] || fail "需要 root，请先 adb root"

mount -o remount,rw / 2>/dev/null || mount -o rw,remount / 2>/dev/null
touch /system/.volte_write_test 2>/dev/null || fail "无法写入 /system"
rm -f /system/.volte_write_test

for f in PhhIms.apk PhhImsOverlay.apk ims-feature.xml privapp.xml; do
    [ -f "$BASE/$f" ] || fail "缺少 $BASE/$f"
done

mkdir -p /system/priv-app/PhhIms
cp -f "$BASE/PhhIms.apk" /system/priv-app/PhhIms/PhhIms.apk || fail "复制 PhhIms.apk 失败"
cp -f "$BASE/ims-feature.xml" /system/etc/permissions/android.hardware.telephony.ims.xml || fail "复制特性声明失败"
cp -f "$BASE/privapp.xml" /system/etc/permissions/privapp-permissions-phh.xml || fail "复制权限白名单失败"
cp -f "$BASE/PhhImsOverlay.apk" /system/product/overlay/PhhImsOverlay.apk || fail "复制 overlay 失败"

chown -R root:root /system/priv-app/PhhIms
chmod 755 /system/priv-app/PhhIms
chmod 644 /system/priv-app/PhhIms/PhhIms.apk
chcon -R u:object_r:system_file:s0 /system/priv-app/PhhIms 2>/dev/null

for f in /system/etc/permissions/android.hardware.telephony.ims.xml \
         /system/etc/permissions/privapp-permissions-phh.xml \
         /system/product/overlay/PhhImsOverlay.apk; do
    chown root:root "$f"; chmod 644 "$f"
    chcon u:object_r:system_file:s0 "$f" 2>/dev/null
done

setprop persist.dbg.volte_avail_ovr 1
setprop persist.dbg.wfc_avail_ovr 1
setprop persist.dbg.allow_ims_off 1
setprop persist.radio.calls.on.ims 1
settings put global enhanced_4g_mode_enabled 1
settings put global hidden_api_policy 1
settings put global hidden_api_policy_p_apps 1
settings put global hidden_api_policy_pre_p_apps 1

rm -rf /data/system/package_cache/* 2>/dev/null
sync
log "安装完成，重启后生效。"
