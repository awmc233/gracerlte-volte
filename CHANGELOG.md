# Changelog

## v1.0.5 — 2026-11-22

### 修复

- **来电全部提示"已关机"**：IMS PDN 换网（net 126 → 141）后，新网络的
  `onAvailable` 回调被 IMS 重连的单飞锁（45 秒持有）当成"重复重连"丢弃，
  旧的 `net=126` 又没有 link properties（`if=none`），于是每 60 秒用旧网络
  空转重连，永远注册不上；网络侧因此把来电转到"关机"提示。
  现场日志：`Suppressing duplicate IMS reconnect: new=new IMS network available
  old=126 new=141 ... existing=SIP watchdog: IMS not ready`，
  之后持续 `Trying to connect ... net=126 if=none`。
  修复：新 IMS 网络可用时，若单飞锁仍被旧网络的重连占用，允许新网络抢占
  （`reconnectIms` 中 clear + 重新 reserve），不再把新网络事件丢弃。

## v1.0.4 — 2026-11-21

### 修复

- **已接通的通话被误判为"网络拒接"后卡死在拨号中**：
  200 OK + ACK 之后如果 2 秒内没收到下行 RTP，旧逻辑会直接 BYE 掉通话，
  且取消回调没有带 `callStartFailed`，`PhhMmTelFeature` 匹配不到拨出监听，
  Telecom 就一直停在 `DIALING`（现场：11:29 那通信令已接通、被 2 秒超时掐断，
  之后 `dumpsys telecom` 一直显示 `state=DIALING`）。
  改动：
  - 下行 RTP 宽限从 2 秒延长到 6 秒
  - 超时取消时补上 `callStartFailed=true`，正确走 `callSessionInitiatingFailed`
  - `outgoingCallSipCallId` 尚未回填时也把取消事件路由到拨出监听，避免事件被丢弃

## v1.0.3 — 2026-11-20

### 修复

- **长时间待机后电话打不通（走了 CS 回落并失败）**：IMS 的"保留注册、按需重连"路径
  会让主 SIP TCP 流长期关闭；注册过期后没有任何机制触发重注册，框架于是把呼叫切到 CS，
  而 LTE-only 的移动网络直接以 `CONGESTION`（cause 49）拒绝。
  新增 SIP 看门狗（`SipHandler.ensureSipWatchdogRunning`）：每 30 秒检查一次，
  以下任一情况立即强制完整重注册：
  - 最近一次成功 REGISTER 超过 20 分钟
  - IMS 已就绪但主 SIP 传输处于空闲/关闭状态
  - IMS 已就绪但 SIP 传输断开

  现场日志（2026-11-20 10:35–10:36）：`useImsForCall=false`、
  `LAST_CALL_FAIL_CAUSE causeCode: 49 vendorCause: 24`、`onDisconnect cause=CONGESTION`；
  应用进程存活但已无任何 SIP 线程/连接，而 IMS 网络请求仍然挂着。

### 变更

- 版本号 `versionCode 52` / `versionName 1.0.3`。

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

### 变更

- APK 版本号提升到 `versionCode 51` / `versionName 1.0.2`。
- 发布 v1.0.2 的 TWRP 卡刷 / `adb sideload` 通用包，`tools/verify.*` 改为接受
  `versionCode >= 50`。

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
