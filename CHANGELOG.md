# Changelog

## v1.0.2 — 2026-11-19

### 修复

- **去电"完全没有反应"**：INVITE 发出后 8 秒内收不到任何 SIP 响应（连 `100 Trying` 都没有）
  即判定失败，发送 CANCEL、以 408 结束通话，并回收 SIP 传输、重新请求 IMS 网络。
  此前这种情况会一直停在"拨号中"（实测可复现：对 P-CSCF 丢包后
  `Send-Q` 积压、`ESTABLISHED` 但永无响应）。
  改动：`SipCallSetupTimers.onOutgoingInviteSent()`、`SipCarrierSettings.noResponseTimeoutMs`、
  `SipHandler.handleOutgoingCallSetupTimeout()`。
- **SIP TCP 健康检测**：给 SIP socket 设置 `TCP_USER_TIMEOUT=8s`、
  keepalive（20s 空闲 / 5s 间隔 / 3 次探测）与 `TCP_NODELAY`，让"半死连接"
  能在内核层被发现并触发既有重连逻辑（`SipConnection`）。

### 已知问题

- **免提按钮在 VoLTE 通话中不改变实际出声**（界面会亮、音量略变，但仍从听筒出声）。
  这是三星音频 HAL 的限制：只有 `MODE_IN_CALL`（CP 通话）才会切换 `voice-*-wb`
  mixer path，而 IMS 通话必须保持 `MODE_IN_COMMUNICATION` 才能让麦克风走 AP 通路。
  详细调查与实验记录见 [`docs/speakerphone-investigation.md`](docs/speakerphone-investigation.md)。

## v1.0.1 — 2026-11-18

### 修复

- `src/privapp-permissions-me.phh.ims.xml` 补齐 `CONNECTIVITY_USE_RESTRICTED_NETWORKS`。
  adb 安装路径此前只写入 2 项白名单，而 APK 会请求该 signature|privileged 权限；在
  `ro.control_privapp_permissions=enforce` 的 ROM 上会抛
  `IllegalStateException: Signature|privileged permissions not in privapp-permissions allowlist`，
  导致 system_server 崩溃、开机循环。卡刷包内原本就是完整白名单，不受影响；本次改动让
  adb 安装与卡刷的行为一致。
- `src/gradlew`、`tools/*.sh` 补上可执行位。此前在 Linux / macOS 上直接
  `./gradlew`、`./tools/install-adb.sh` 会 permission denied。
- 新增的 `tools/verify.ps1` 以 **UTF-8 with BOM** 保存：Windows PowerShell 5.1 会把无 BOM 的
  UTF-8 当 ANSI 读，中文串里的字节被解成弯引号，导致脚本解析失败（`install-adb.ps1` 原本就带 BOM，
  无需改动）。
- 单元测试 `SipRegisteredIdentityTest` 的 Service-Route 断言与实现不符：实现按 RFC 3608
  原样使用 `service-route`，测试却期望去掉 `;transport=udp`。已更新断言，97 个单测全部通过。

### 新增

- 生成 TWRP 卡刷 / `adb sideload` 通用的安装包
  `gracerlte-VoLTE-v50-TWRP-sideload.zip`（作为发布资产单独分发，不纳入仓库）。
- `tools/verify.sh`（Linux / macOS / WSL）与 `tools/verify.ps1`（Windows）：安装后逐项校验
  APK 版本、overlay、VoLTE 属性、IMS 特性、注册日志与 IMS PDN，带退出码，方便脚本化。
- `README.en.md`：英文版 README，中文 README 里加了语言切换。
- `.github/workflows/build.yml`：GitHub Actions，push tag 或手动触发时跑单测、构建 APK，
  打 tag 时自动把 APK 挂到 Release。
- README 徽章换成指向真实仓库与 Release 的链接（GitHub / release / platform / license）。

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
