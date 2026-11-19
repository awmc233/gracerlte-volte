# gracerlte VoLTE — 安装后验证脚本（Windows / PowerShell）
#
# 用法:
#   .\tools\verify.ps1                 # 默认 adb、默认设备
#   .\tools\verify.ps1 -Serial <sn>    # 指定设备
#   $env:ADB = "C:\path\to\adb.exe"; .\tools\verify.ps1
#
# 退出码: 0 = 全部通过；1 = 有关键项失败

param(
    [string]$Serial = ""
)

$ErrorActionPreference = "Continue"
$AdbBin = if ($env:ADB) { $env:ADB } else { "adb" }

function Adb {
    if ($Serial) { & $AdbBin -s $Serial @args } else { & $AdbBin @args }
}

function Trim-Text([string]$s) { if ($null -eq $s) { "" } else { $s.Trim() } }

$script:Pass = 0
$script:Fail = 0
$script:Warn = 0

function Ok([string]$msg)   { $script:Pass++; Write-Host "  [ OK ] $msg" -ForegroundColor Green }
function Bad([string]$msg)  { $script:Fail++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Warn([string]$msg) { $script:Warn++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Info([string]$msg) { Write-Host "  ..     $msg" -ForegroundColor DarkGray }

Write-Host "== gracerlte VoLTE 验证 =="

# 0. adb 可用、设备在线
if (-not (Get-Command $AdbBin -ErrorAction SilentlyContinue)) {
    Write-Host "找不到 adb（可用 `$env:ADB 指定完整路径）" -ForegroundColor Red
    exit 1
}

$state = Trim-Text ((Adb get-state 2>$null | Out-String))
if ($state -eq "device") {
    $dev = Trim-Text ((Adb shell getprop ro.product.device 2>$null | Out-String))
    Ok "设备在线 ($dev)"
} else {
    Bad "设备不在线（adb get-state = $state）"
    Write-Host ""
    Write-Host "结果: $script:Pass 通过 / $script:Fail 失败 / $script:Warn 警告"
    exit 1
}

# 1. APK 版本
$ver = Trim-Text ((Adb shell dumpsys package me.phh.ims 2>$null | Out-String))
$verLine = ($ver -split "`n" | Where-Object { $_ -match 'versionCode=' } | Select-Object -First 1)
if ($verLine -match 'versionCode=(\d+)') {
    $code = [int]$Matches[1]
    if ($code -ge 50) {
        Ok "PhhIms 已安装，versionCode=$code（要求 >=50）"
    } else {
        Bad "版本过低: versionCode=$code（要求 >=50）"
    }
} else {
    Bad "查不到 me.phh.ims（未安装？）"
}

# 2. RRO overlay
$overlay = (Adb shell cmd overlay list 2>$null | Out-String)
if ($overlay -match '\[x\].*me\.phh\.ims\.overlay') {
    Ok "overlay 已启用"
} else {
    Bad "overlay me.phh.ims.overlay 未启用"
}

# 3. VoLTE 开关属性
$volte = Trim-Text ((Adb shell getprop persist.dbg.volte_avail_ovr 2>$null | Out-String))
if ($volte -eq "1") {
    Ok "persist.dbg.volte_avail_ovr = 1"
} else {
    Bad "persist.dbg.volte_avail_ovr = $volte（期望 1）"
}

# 4. IMS 特性声明
$features = (Adb shell pm list features 2>$null | Out-String)
if ($features -match 'android\.hardware\.telephony\.ims') {
    Ok "IMS 特性已声明"
} else {
    Bad "缺少 android.hardware.telephony.ims 特性"
}

# 5. IMS 注册日志
$logcat = (Adb logcat -b all -d 2>$null | Out-String)
$reg = ($logcat -split "`n" | Where-Object { $_ -match 'IMS registration ready|REGISTRATION_STATE_REGISTERED' } | Select-Object -Last 2)
if ($reg) {
    Ok "日志里有 IMS 注册成功记录"
    $reg | ForEach-Object { Write-Host "          $($_.Trim())" }
} else {
    Warn "日志里没找到注册成功记录（可能刚重启、尚未注册）"
}

# 6. IMS PDN
$conn = (Adb shell dumpsys connectivity 2>$null | Out-String)
if ($conn -match 'extra: ims') {
    Ok "IMS PDN 已建立"
} else {
    Warn "dumpsys connectivity 里没看到 extra: ims"
}

# 7. 当前注册状态
$tel = (Adb shell dumpsys telephony.registry 2>$null | Out-String)
$stLine = ($tel -split "`n" | Where-Object { $_ -match 'mImsRegistrationState' } | Select-Object -First 1)
if ($stLine) { Info "注册状态: $($stLine.Trim())" }

Write-Host ""
Write-Host "结果: $script:Pass 通过 / $script:Fail 失败 / $script:Warn 警告"
if ($script:Fail -eq 0) {
    Write-Host "基础检查通过。请再拨测一通去电与来电，确认双向音频。" -ForegroundColor Green
    exit 0
}
Write-Host "有检查未通过，请按提示排查（见 README / docs/IMS-VoLTE-诊断报告.md）。" -ForegroundColor Red
exit 1
