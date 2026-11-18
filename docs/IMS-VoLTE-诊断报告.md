# gracerlte (Galaxy Note FE) LineageOS 20.0 — VoLTE / IMS 失效诊断报告

- **设备**：SM-N935F，代号 `gracerlte`，Exynos 8890
- **ROM**：`lineage-20.0-20250628-UNOFFICIAL-gracerlte`（userdebug / Android 13 / TQ3A.230901.001）
- **运营商**：中国移动 CMCC，MCC/MNC 460/02，carrierId `1435`
- **现象**：4G 数据正常；无法 VoLTE 通话；IMS 不注册

---

## 一、结论

**不是"IMS 注册失败"，而是"IMS 从未启动"。**

开机时 telephony 框架判定本机"不支持 IMS"，直接跳过了 ImsResolver 的创建；ROM 中也不存在任何 ImsService 实现。因此上层从来没有发起过 SIP REGISTER，也没有建立 `ims` APN，自然不存在注册状态。

---

## 二、决定性证据

### 1. 开机日志（system_server → phone 进程）

```
I/PhoneFactory( 4498): IMS is not supported on this device, skipping ImsResolver.
```

这是 AOSP `PhoneFactory` 在 `PackageManager.hasSystemFeature(FEATURE_TELEPHONY_IMS) == false`
时打印的分支。ImsResolver 不创建 ⇒ 不会绑定任何 ImsService ⇒ 不会有 MmTelFeature。

### 2. 缺少 `android.hardware.telephony.ims` 系统特性

```
$ adb shell pm list features | grep telephony
feature:android.hardware.telephony
feature:android.hardware.telephony.calling
feature:android.hardware.telephony.data
feature:android.hardware.telephony.gsm
feature:android.hardware.telephony.messaging
feature:android.hardware.telephony.radio.access
feature:android.hardware.telephony.subscription
```

没有 `android.hardware.telephony.ims`。

进一步定位：ROM 只拷入了 GSM 的标准特性文件，没有 IMS 的特性文件。

```
/vendor/etc/permissions/android.hardware.telephony.gsm.xml
  <feature name="android.hardware.telephony" />
  <feature name="android.hardware.telephony.radio.access" />
  <feature name="android.hardware.telephony.subscription" />
  <feature name="android.hardware.telephony.gsm" />
  <feature name="android.hardware.telephony.calling" />
  <feature name="android.hardware.telephony.data" />
  <feature name="android.hardware.telephony.messaging" />
```

`find /system -iname '*ims*'` 中也没有 `android.hardware.telephony.ims.xml`。

### 3. 没有任何 ImsService 实现

```
$ adb shell pm path com.android.ims
(空)

$ adb shell dumpsys package com.android.ims
Unable to find package: com.android.ims
```

`/system/priv-app`、`/system/app`、`/system/system_ext/priv-app` 全部列出，没有 `ImsService`。
`find` 的结果里只有：

```
/system/product/priv-app/ImsServiceEntitlement/...      ← 运营商 IMS 开通(entitlement)客户端，不提供 MmTel
/system/product/overlay/ImsServiceEntitlement__...
/system/framework/ims-common.jar                        ← 只是 ims 的公共接口库
```

也没有 `libims.so` / `libsecims.so` 之类的 IMS native 库。
唯一在跑的是 `com.android.service.ims/.RcsService`（RCS 服务），不含语音 IMS。

### 4. 运营商配置同样没有打开 VoLTE

CarrierConfig 中 CMCC（carrierId 1435）的配置（`carrier_config_carrierid_1435_China-Mobile.xml`）只有：

```xml
<boolean name="allow_emergency_numbers_in_call_log_bool" value="true"/>
<boolean name="support_tdscdma_bool" value="true"/>
...
```

没有 `carrier_volte_available_bool=true`，而该键默认值为 `false`。
（APN 侧反而是齐的：`/product/etc/apns-conf.xml` 中 46002 有 `<apn carrier="IMS" apn="ims" type="ims"/>`，所以 APN 不是瓶颈。）

### 5. 底层其实有 Samsung 的私有 IMS 通道，但上层没有客户端

lshal 能看到 Samsung 私有的 IMS 控制通道：

```
vendor.samsung.hardware.radio.channel@2.0::ISehChannel/imsd
vendor.samsung.hardware.radio.channel@2.0::ISehChannel/imsd2
vendor.samsung.hardware.radio@2.1::ISehRadio/slot1
```

`libsec-ril.so` 内含 Samsung 的 IMS OEM 命令：

```
IMS_REGI  IMS_REGISTRATION_STATE  IMS_SIP_PORT  IMS_FQDN_CSCF
IMS_AUTH  IMS_VOLTE_SIM  IMS_HVOLTE_SWITCH  IMS_ENGINE ...
```

也就是说：**modem / vendor 侧具备 Samsung 私有 IMS 能力，但 LineageOS 没有携带 Samsung 的 IMS 客户端**
（官方固件里的 `com.sec.ims` / ImsService 属于 TouchWiz 框架，依赖三星私有 framework 类，无法直接在 AOSP 上运行）。

同时，vendor manifest 里也**没有** AOSP 标准 IMS HAL：

```
android.hardware.radio@1.4::IRadio/slot1     ← 只有普通 RIL
（没有 android.hardware.radio.ims）
```

---

## 三、因果链

```
缺 android.hardware.telephony.ims.xml
        │
        ▼
PackageManager.hasSystemFeature("android.hardware.telephony.ims") == false
        │
        ▼
PhoneFactory 打印 "IMS is not supported ... skipping ImsResolver"，不创建 ImsResolver
        │
        ▼
没有任何 ImsService 被绑定 → 没有 MmTelFeature → 没有 ImsPhoneCallTracker
        │
        ▼
不发起 SIP REGISTER、不建立 ims PDN
        │
        ▼
VoLTE / VoWiFi / VoNR 全部不可用；通话只能回落 2G/3G 电路域
```

**4G 数据为什么正常**：数据业务走 `libsec-ril.so` → `android.hardware.radio@1.4` 的 `SETUP_DATA_CALL`，
是完全独立于 IMS 的 PS 通路。IMS 缺失只影响"LTE 承载语音"，不影响数据。

---

## 四、为什么这不是"改个开关"能修好的

即便补上 feature 声明，ImsResolver 也只会绑定到空的 ImsService 集合；而：

1. AOSP 的参考 IMS 实现（`com.android.ims` + `libims`）在这个 ROM 里根本不存在，需要额外集成；
2. 该机是非 Treble 设备（`ro.treble.enabled=false`），vendor 只提供 Samsung 私有 `ISehChannel/imsd`，
   不提供 AOSP `android.hardware.radio.ims` HAL，AOSP 的 ImsService 无法直接驱动这套 modem；
3. 中国移动 VoLTE 还依赖 AKA 鉴权 / IPsec / 专用 SIP 参数，通用开源 IMS 未必能过。

LineageOS 官方对 IMS 的说明也一致：IMS 没有标准 AOSP 实现，依赖厂商私有实现的设备不支持相关功能
（<https://wiki.lineageos.org/quirks/ims/>）。

---

## 五、可行的修复路线（按可行性排序）

### 方案 A：集成 PhhIms（目前唯一现实的软件方案）

社区已有针对"Samsung Exynos + LineageOS"的 PhhIms 方案（<https://github.com/zombienerd8000/voLTE-exynos>），
其 README 描述的根因与本报告完全一致：**缺少 `android.hardware.telephony.ims` 声明导致 ImsResolver 不创建**。

需要同时补齐：

| 组件 | 作用 |
|---|---|
| `PhhIms.apk` | 开源 IMS 实现，作为 MmTel provider |
| `/system/etc/permissions/android.hardware.telephony.ims.xml` | 让 ImsResolver 在开机时创建 |
| `privapp-permissions-phh.xml` | 授予 `BIND_IMS_SERVICE` 等特权权限 |
| `PhhImsOverlay.apk` | 覆盖 `config_ims_mmtel_package=me.phh.ims` |
| CarrierConfig 覆盖（46002） | `carrier_volte_available_bool=true`、`carrier_volte_provisioned_bool=true` |
| 音频路由修正 | Samsung audio HAL 会把 mic 切到 `MODE_IN_CALL`（modem 通路），PhhIms 收不到上行语音 |

注意：
- 该方案在原项目上验证于 LineageOS 23.2 / Exynos 990，**本机是 LineageOS 20 / Exynos 8890，且是 CMCC**，成功率未知；
- 需要 root（Magisk/APatch）或直接改 `/system`；
- 通话可能"能听到对方、对方听不到你"，需要音频 watcher 修正。

### 方案 B：回到官方固件 / OneUI 移植 ROM

官方固件自带 Samsung IMS；任何基于官方固件的移植 ROM 都能保留 VoLTE。代价是失去 LineageOS 的纯净与更新。

### 方案 C：自行移植 Samsung IMS

需要三星私有 framework 类与 native 库，工作量极大，不建议。

---

## 六、复现 / 验证命令

```bash
adb root
adb shell pm list features | grep telephony.ims          # 期望：无输出
adb shell pm path com.android.ims                        # 期望：空
adb shell dumpsys package com.android.ims                # 期望：Unable to find package
adb logcat -b all -d | grep -i "ImsResolver"             # 期望：IMS is not supported ... skipping
adb shell dumpsys carrier_config | grep -i carrier_volte # 期望：carrier_volte_available_bool = false
adb shell lshal | grep -i ims                            # 期望：只有 ISehChannel/imsd，无 radio.ims
```

---

## 七、插卡后的实时验证（CMCC 46000 / LTE，2026-11-17 17:10）

SIM 就位后，LTE 与数据均正常，但 IMS 侧的状态与上面的静态分析完全吻合：

```
# 业务状态：LTE 已注册、数据已连接
mServiceState={mVoiceRegState=0(IN_SERVICE), mDataRegState=0(IN_SERVICE),
               ... getRilVoiceRadioTechnology=14(LTE), getRilDataRadioTechnology=14(LTE),
               ... mOperatorAlphaLong=CHINA MOBILE}
mDataConnectionState=2

# IMS 状态：始终未注册
D Phone   : isImsRegistered =false
D Phone   : getImsRegistrationTechnology =-1
D Phone   : isImsCapabilityAvailable, capability=1, regTech=1, isAvailable=false
D RILD    : ReqSetPreferredNetworkType: Ims not registered
D RILJ    : [1018]< IMS_REGISTRATION_STATE {0, 2}      ← modem 回“未注册”，框架无人消费

# 没有任何 ImsService 被绑定
dumpsys activity services | grep -c ImsService  →  0
（只有 com.android.service.ims/.RcsService 在跑）

# 运营商配置：CMCC 配置已生效，但 VoLTE 开关仍为 false
D DNC-0   : onCarrierConfigUpdated: config is carrier specific. mSimState=LOADED
carrier_volte_available_bool = false
carrier_volte_provisioned_bool = false
config_ims_mmtel_package_override_string = null

# IMS APN 已经建好 profile，但从未建立 IMS PDN
D DPM-0   : Added [DataProfile=[ApnSetting] IMS, 3523, 46002, ims, ..., type=ims, IPV4V6]
（实际连上的只有 CMNET：preferapn = CMNET, type=default,supl,xcap）
```

这说明：
1. 卡、LTE、数据都正常，问题确实只在 IMS 侧；
2. 框架层 `isImsRegistered=false`、`getImsRegistrationTechnology=-1`，且 ImsService 绑定数为 0；
3. 即使运营商配置已按 carrierId 1435 正确加载，`carrier_volte_available_bool` 仍是 `false`；
4. 调制解调器能响应 `IMS_REGISTRATION_STATE`，但上层没有 IMS 客户端去发起注册；
5. `ims` APN 的 profile 存在，但由于没有 IMS 客户端请求，IMS PDN 从未建立。

## 九、实机修复实验记录（2026-11-17，已完成）

### 9.1 已实现的修复

| 步骤 | 内容 | 结果 |
|---|---|---|
| 1 | 向 `/system/etc/permissions/` 补 `android.hardware.telephony.ims.xml` | `ImsResolver` 被创建 |
| 2 | 用 `Daniel-5352/phhims-exynos8890`（专为 Exynos 8890 的 PhhIms fork）源码，按 Android 13 重新构建 APK | 可安装、可绑定 |
| 3 | 安装为 `/system/priv-app/PhhIms/` + privapp 白名单 | `BIND_IMS_SERVICE`、`READ_PRIVILEGED_PHONE_STATE`、`CONNECTIVITY_USE_RESTRICTED_NETWORKS` 生效 |
| 4 | 构建 RRO `PhhImsOverlay`（target `com.android.phone`）设置 `config_ims_mmtel_package=me.phh.ims` | `ImsResolver: device MMTEL package: me.phh.ims` |
| 5 | 设置 `persist.dbg.volte_avail_ovr` 等属性、`enhanced_4g_mode_enabled=1` | 框架允许 VoLTE |

关键构建适配（原仓库产物是 Android 16 的，AAPT2 资源表 A13 读不了）：

- 去掉 `sharedUserId="android.uid.system"`（ROM 平台密钥不可得，改走 priv-app + 白名单）；
- `SubscriptionManager.getSubscriptionId(int)` 是 Android 14+ API，替换为 `getSubId(slot)?.firstOrNull()`；
- `RegistrationCellInfoLogger` 的 `getAllCellInfo()` 会抛 `SecurityException` 并中断注册，改为容错；
- AMR 编码器补 `KEY_MAX_INPUT_SIZE=16384`，修复 `BufferOverflowException`；
- CMCC profile 关闭 `use_precondition`，修复 UPDATE 被回 `400 SDP is illegal`。

### 9.2 实测结果

成功：

```
I/ImsResolver: device MMTEL package: me.phh.ims
I/ImsResolver: Binding ImsService: ComponentInfo{me.phh.ims/me.phh.ims.PhhImsService} with features: [{s=0, f=MMTEL}]
I/PHH SipHandler: IMS registration ready: REGISTER 200 OK
D/ImsRegCallbackHelper: REGISTERING -> REGISTERED
D/ImsPhone: handleImsRegistered: onImsMmTelConnected imsRadioTech=WWAN
ConnectivityService: NetworkAgentInfo ... ni{MOBILE[LTE] CONNECTED extra: ims}
```

VoLTE 呼叫：`INVITE → 183 → ACTIVE`，AMR-NB（`pt=97`）下行 RTP 正常，通话可以建立并听到对方。

最终上行音频也打通了：

```
D/PHH SipHandler: setMode(IN_COMMUNICATION): before=3 after=3 err=none
D/PHH SipHandler: AudioRecord started, state=3 audioMode=3 (was 3) preferredDevice=null
D/PHH SipHandler: AudioRecord.read nRead=1408 allZero=false (bufferSize=1408)
```

### 9.3 上行音频的关键根因

AOSP 13 的 `AudioService.setMode()` 有一条容易踩的规则（`getAudioModeOwnerHandler()`）：

> 音频模式的所有者 = **最近一个特权（持 MODIFY_PHONE_STATE）的调用者**；没有特权调用者时才取最近的非特权调用者。

电话进程（uid 1001）在通话中持有**特权**的 `MODE_IN_CALL`。PhhIms 作为普通 priv-app 只能以非特权身份请求
`MODE_IN_COMMUNICATION`，因此永远被压在下面——`setMode(3)` 不抛异常，但 `getMode()` 仍是 2，
`AudioRecord` 于是在 `MODE_IN_CALL` 的路由下打开，读到全零。

修复只需一步：让 PhhIms **请求 `android.permission.MODIFY_PHONE_STATE`**（`signature|privileged`，
privapp 白名单里本来就有）。授予后 PhhIms 成为"最近的特权调用者"，`MODE_IN_COMMUNICATION` 生效。

配套的两个必要改动：

- 去掉 `AudioRecord.setPreferredDevice(builtinMic)`：通话中被钉住的内建 mic 输入会被 HAL 静音，交给音频策略选路反而正常；
- 采集源优先 `MIC`，并保留 40 ms 的 `SipAudioModeEnforcer` 作为兜底（现在 `setMode` 已能保持，兜底基本不触发）。

### 9.4 第二个问题：部分号码接通 1 秒后被 487 挂断

现象：拨打 A 号码正常，拨打 B 号码振铃约 1 秒后网络回 `487 Request Terminated`，
warning 为 `399 ... "SDP is illegal"`。

抓包定位：B 号码的 SBC 在振铃期间下发 **UPDATE（带 SDP offer）**，PhhIms 回 `200 OK` 后被判非法。
逐项对比 offer/answer 后，问题出在 UPDATE 的 SDP answer 生成器（`SipUpdateSdpAnswerBuilder`）：

| 问题 | 说明 |
|---|---|
| 缺少结尾 CRLF | INVITE 的 SDP 以 `\r\n` 结尾，UPDATE answer 却直接 `joinToString("\r\n")`，严格 SBC 解析失败 |
| `o=` 用了带 `+` 的手机号 | INVITE 用 `o=- 1 2`，answer 却用 `o=+86187...`，与 SBC 的会话描述不一致 |
| `b=AS` 大于 offer | offer 的 m 级 `b=AS:49`，answer 却写 `b=AS:88` |
| 无条件回 precondition | offer 没有 `a=curr/des/conf:qos`，answer 却带上，属 offer/answer 违规 |

修复：answer 改为 `o=-`、去掉 `b=AS`、按 offer 是否含 precondition 决定是否回 qos 属性、
并补上结尾 `\r\n`。修复后该号码正常接通，且协商到 **AMR-WB（HD）**。

```
UPDATE answer SDP offerPrecondition=false
v=0|o=- 1 4 IN IP6 ...|s=phh voice call|c=IN IP6 ...|t=0 0
m=audio 35293 RTP/AVP 98 101|a=rtpmap:98 AMR-WB/16000/1|a=ptime:20|a=maxptime:240
a=rtpmap:101 telephone-event/16000|a=fmtp:98 mode-change-capability=2;max-red=0
a=fmtp:101 0-15|a=sendrecv
```

### 9.5 第三个问题：来电接听后立刻挂断

现象：别人打进来，点接听后约 1 秒对方挂断。

日志显示来电流程其实走到了：`200 OK（SDP）→ ACK → 媒体启动`，紧接着对端发来一个
**in-dialog re-INVITE**（`cseq=348757`，带 SDP offer），我们回 `200 OK` 后，对端在 ~100 ms 内直接发 **BYE**。

原因与 9.4 同源：`SipInDialogInvite.buildAnswerSdp()` 生成的 SDP 同样**缺少结尾 CRLF**：

```kotlin
return answerSdpLines.joinToString("\r\n").toByteArray(Charsets.US_ASCII)   // 少了 + "\r\n"
```

修复：补上结尾 `\r\n`（同时修掉 `SipOutgoingDialogSdp` 里一处相同的写法），并打印完整 answer SDP。
修复后来电正常保持，双方音频正常：

```
Sending response=200 ... bodyBytes=553        (initial INVITE)
Received request=ACK ...
Replying to in-dialog INVITE with response=200 ... bodyBytes=350
In-dialog INVITE answer SDP: v=0|o=- 1 3 IN IP6 ...|m=audio 59392 RTP/AVP 104 96|b=AS:90|...
Received request=ACK ...                       (re-INVITE accepted)
Received request=BYE cseq=297259               (caller hung up normally after ~14 s)
Encode thread exiting: totalPacketsSent=681
```

### 9.6 产物与回滚

- 构建产物：`analysis/phh/PhhIms_a13.apk`（versionCode 50，含上行音频、去电 UPDATE 与来电 re-INVITE 的 SDP 修复）
- 安装脚本：`analysis/phase1.sh`、`phase2.sh`、`phase3.sh`
- 回滚脚本：`analysis/rollback.sh`（删除 IMS 声明 / PhhIms / overlay，复位属性，重启即可恢复原状）

```bash
adb root
adb push analysis/rollback.sh /data/local/tmp/rollback.sh
adb shell sh /data/local/tmp/rollback.sh
adb reboot
```

注意：回滚后 IMS 注册会消失，通话回到 2G/3G 回落（音质差但双向可通）；
保留当前状态则是"能注册、能接通、只有下行音频"。两种取舍需要按使用场景决定。

## 十、附：实验前的实机状态

- 抓取时设备 `gsm.sim.state=ABSENT`、`ril.hasisim=0`、`RILD: GetImsi is empty`，
  SIM 卡当前不在位；订阅库里仍保留 CMCC 46002 记录（carrierId 1435）。
- 实机 `/`（SYSTEM 分区）为 ext4 且可 `remount,rw`，`adb root` 可用（userdebug），
  因此具备直接向 `/system` 补文件的实验条件（改前建议先备份，改后需重启）。
