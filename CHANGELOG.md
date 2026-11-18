# Changelog

## v1.0.1 — 2026-11-18

### 修复

- `src/privapp-permissions-me.phh.ims.xml` 补齐 `CONNECTIVITY_USE_RESTRICTED_NETWORKS`。
  adb 安装路径此前只写入 2 项白名单，而 APK 会请求该 signature|privileged 权限；在
  `ro.control_privapp_permissions=enforce` 的 ROM 上会抛
  `IllegalStateException: Signature|privileged permissions not in privapp-permissions allowlist`，
  导致 system_server 崩溃、开机循环。卡刷包内原本就是完整白名单，不受影响；本次改动让
  adb 安装与卡刷的行为一致。

### 新增

- 生成 TWRP 卡刷 / `adb sideload` 通用的安装包
  `gracerlte-VoLTE-v50-TWRP-sideload.zip`（作为发布资产单独分发，不纳入仓库）。

## v1.0.0 — 2026-11-18

首个公开版本。将一台"系统层面没有 IMS 栈"的 LineageOS 20 三星 Note FE 改造为可正常使用中国移动 VoLTE：
IMS 注册、去电、来电、双向音频全部打通。

### 新增

- Android 13 构建的 PhhIms（versionCode 50）与 framework RRO
- TWRP 卡刷包 `twrp/gracerlte-VoLTE-v50-TWRP.zip`
- adb 安装脚本（Windows / Linux / macOS）
- MindTheGapps 兼容性补丁脚本（不重分发 GApps）
- 完整诊断报告（PDF / Markdown）与项目复盘

### 修复（按发现顺序）

1. 补 `android.hardware.telephony.ims` 特性，使 `ImsResolver` 启动
2. 重新用 SDK 33 构建，解决 Android 16 产物在 A13 上的资源表不兼容
3. 去掉不可用的 `sharedUserId`，改走 priv-app + 权限白名单
4. 替换 Android 14+ 的 `SubscriptionManager.getSubscriptionId`
5. 修复 `getAllCellInfo()` 的 `SecurityException` 中断注册
6. 补 `CONNECTIVITY_USE_RESTRICTED_NETWORKS`，使 IMS PDN 可建立
7. 修复 AMR 编码器 `BufferOverflowException`
8. CMCC profile 关闭 precondition，修复 `400 SDP is illegal`
9. 上行全零：补 `MODIFY_PHONE_STATE` 成为 AudioService 特权 mode owner，
   去掉 `preferredDevice` 绑定，采集源优先 MIC
10. 部分号码去电 `487 SDP is illegal`：UPDATE answer 补 CRLF、`o=-`、去掉 `b=AS`、按需回 precondition
11. 来电接听即挂断：re-INVITE answer 补 CRLF
12. hidden API 白名单豁免 `me.phh.ims`

### 已知限制

- 无 VoWiFi / 视频通话
- 未编原生 AEC/RNNoise，免提可能有回声
- 仅验证中国移动
