# gracerlte VoLTE — adb installer (Windows)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Tmp = Join-Path $Root ".tmp"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$env:TEMP = $Tmp
$env:TMP = $Tmp

$Adb = "adb"
if (Get-Command adb -ErrorAction SilentlyContinue) { $Adb = "adb" }

function Fail([string]$msg) { Write-Host "[volte][错误] $msg" -ForegroundColor Red; exit 1 }
function Info([string]$msg) { Write-Host "[volte] $msg" -ForegroundColor Cyan }

Info "检查设备..."
$devices = & $Adb devices 2>$null | Out-String
if ($devices -notmatch "(?m)^\S+\s+device\s*$") { Fail "未检测到已授权设备" }

Info "获取 root..."
& $Adb root 2>$null | Out-Null
Start-Sleep -Seconds 2
& $Adb wait-for-device
$id = (& $Adb shell id 2>$null | Out-String)
if ($id -notmatch "uid=0") { Fail "adb root 失败（需要 userdebug 系统）" }

Info "推送文件..."
& $Adb shell "mkdir -p /data/local/tmp/volte" | Out-Null
& $Adb push "$Root\prebuilt\PhhIms-50.apk"                 "/data/local/tmp/volte/PhhIms.apk" | Out-Null
& $Adb push "$Root\prebuilt\PhhImsOverlay-50.apk"          "/data/local/tmp/volte/PhhImsOverlay.apk" | Out-Null
& $Adb push "$Root\src\android.hardware.telephony.ims.xml" "/data/local/tmp/volte/ims-feature.xml" | Out-Null
& $Adb push "$Root\src\privapp-permissions-me.phh.ims.xml" "/data/local/tmp/volte/privapp.xml" | Out-Null
& $Adb push "$Root\tools\device-install.sh"                "/data/local/tmp/volte/install.sh" | Out-Null

Info "执行安装..."
& $Adb shell "sh /data/local/tmp/volte/install.sh"
if ($LASTEXITCODE -ne 0) { Fail "安装脚本失败" }

Info "重启..."
& $Adb reboot | Out-Null
Start-Sleep -Seconds 5
& $Adb wait-for-device

Info "等待开机..."
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $b = ((& $Adb shell getprop sys.boot_completed 2>$null) -join "").Trim()
    if ($b -eq "1") { break }
}
Start-Sleep -Seconds 20

Info "验证："
& $Adb shell 'dumpsys package me.phh.ims | grep versionCode; cmd overlay list | grep me.phh.ims.overlay; getprop persist.dbg.volte_avail_ovr; logcat -b all -d | grep -E "IMS registration ready|REGISTERED" | tail -2'

Write-Host ""
Write-Host "[volte] 完成。出现 REGISTER 200 OK / REGISTERED 即可拨测。" -ForegroundColor Green
