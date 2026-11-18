# gracerlte VoLTE 改造项目总结

> 设备：Samsung Galaxy Note FE（SM-N935F / `gracerlte`，Exynos 8890）
> 系统：LineageOS 20.0-20250628-UNOFFICIAL（Android 13）
> 运营商：中国移动 CMCC 46002（carrierId 1435）
> 时间：2026-11-17，约 3 小时（16:46 开始诊断，19:33 来电双向通话验证通过）

---

## 一、结果

**成功。** 这台原本完全不支持 VoLTE 的 LineageOS 设备，现在可以：

- IMS 正常注册（`REGISTER 200 OK`，`ims` PDN `CONNECTED`）
- **去电** VoLTE 通话，双向音频正常
- **来电** 接听正常，不再挂断，双向音频正常
- 协商到 **AMR-WB 高清语音**（`PROPERTY_HIGH_DEF_AUDIO`）
- 重启后保持（改动都在 `/system`，属性为 `persist`）

---

## 二、起点：为什么原本不支持

**现象**：4G 数据正常，但 IMS 不注册、无法 VoLTE 通话。

**根因**：这个 ROM 里根本没有 IMS 客户端栈。开机日志一句话定案：

```
I/PhoneFactory( 4498): IMS is not supported on this device, skipping ImsResolver.
```

证据链：

| 检查 | 结果 |
|---|---|
| `android.hardware.telephony.ims` 特性 | 缺失（`pm list features` 无、无对应 permission xml） |
| ImsService | 无（`pm path com.android.ims` 为空） |
| IMS 库 | 无 `libims` / `libsecims` |
| Vendor 侧 | 只有三星私有的 `ISehChannel/imsd`、`ISehRadio`，没有 AOSP `android.hardware.radio.ims` |
| Carrier config | CMCC 的 `carrier_volte_available_bool=false` |
| APN | `ims` APN 是齐的，不是瓶颈 |

**4G 为什么正常**：数据走 `libsec-ril` → `radio@1.4` 的 `SETUP_DATA_CALL`，与 IMS 完全无关。

---

## 三、方案选择

- 三星私有 IMS（TouchWiz 的 `com.sec.ims`）依赖私有 framework 类和平台签名，**无法移植**到 AOSP。
- 选择 **PhhIms**（开源 IMS 实现），使用社区现成的 Exynos 8890 fork：`Daniel-5352/phhims-exynos8890`。
- 需要补齐的组件：IMS 特性声明、ImsService APK、privapp 权限白名单、RRO overlay（`config_ims_mmtel_package`）、VoLTE 属性、音频路由。

---

## 四、逐个攻破的问题

### 阶段 1：让 ImsResolver 启动

| # | 问题 | 修复 |
|---|---|---|
| 1 | 无 `android.hardware.telephony.ims` 特性 | 补 `/system/etc/permissions/android.hardware.telephony.ims.xml` |
| 2 | 无 ImsService | 引入 PhhIms |
| 3 | 原仓库 APK 是 Android 16 构建，A13 资源表读不了（offset16） | 用 JDK 17 + SDK 33 重新编译 |
| 4 | manifest 用 `sharedUserId=android.uid.system`，平台密钥不匹配 | 去掉 sharedUserId，改走 priv-app + privapp 白名单 |
| 5 | A14+ API `SubscriptionManager.getSubscriptionId(int)` | 换成 `getSubId(slot)?.firstOrNull()` |
| 6 | `getAllCellInfo()` 抛 `SecurityException` 中断注册 | 改成容错（只是调试日志） |
| 7 | 缺 `CONNECTIVITY_USE_RESTRICTED_NETWORKS`，IMS PDN 请求被拒 | manifest 补权限 + 白名单 |
| 8 | 系统 APK 更新后 PM 不重新解析（版本/权限不生效） | 提升 versionCode + 清 `/data/system/package_cache` |
| 9 | privapp 白名单带 UTF-8 BOM → SystemConfig 解析失败 → system_server 崩溃 | 去掉 BOM（**踩过的最大坑**） |

结果：`ImsResolver: device MMTEL package: me.phh.ims` → `Binding ImsService ... MMTEL` → `REGISTER 200 OK`。

### 阶段 2：让通话能建立

| # | 问题 | 修复 |
|---|---|---|
| 10 | CMCC 对带 precondition 的 UPDATE 回 `400 SDP is illegal` | CMCC profile 关闭 `use_precondition` |
| 11 | AMR 编码器 `BufferOverflowException`（进程崩溃） | 设 `KEY_MAX_INPUT_SIZE=16384` |
| 12 | 部分号码接通 1 秒被 `487 SDP is illegal` | UPDATE 的 SDP answer：补结尾 CRLF、`o=-`、去掉 `b=AS`、按 offer 决定是否回 precondition |
| 13 | 来电接听即挂断 | re-INVITE 的 SDP answer 同样缺结尾 CRLF，补上 |

### 阶段 3：让声音双向

| # | 问题 | 修复 |
|---|---|---|
| 14 | 上行 `AudioRecord` 读到全零 | 见下 |

**上行的真正根因**（最隐蔽的一个）：

AOSP 13 `AudioService.setMode()` 的 mode owner 规则是——

> 音频模式所有者 = **最近一个持有 `MODIFY_PHONE_STATE` 的特权调用者**；没有特权调用者时才取非特权的。

电话进程持有特权的 `MODE_IN_CALL`，PhhIms 作为普通 priv-app 的 `MODE_IN_COMMUNICATION` 永远被压住。
`setMode(3)` 不抛异常、也不报错，但 `getMode()` 仍是 2，录音流在 `MODE_IN_CALL` 下打开 → 全零。

修复：给 PhhIms 请求 `MODIFY_PHONE_STATE`，成为"最近的特权调用者"；同时：

- 去掉 `AudioRecord.setPreferredDevice(builtinMic)`（通话中被钉住的输入会被静音）
- 采集源优先 `MIC`
- 保留 40 ms 的 `SipAudioModeEnforcer` 兜底

---

## 五、最终验证

```
ImsResolver: device MMTEL package: me.phh.ims
Binding ImsService: me.phh.ims/PhhImsService (MMTEL)
PHH SipHandler: IMS registration ready: REGISTER 200 OK
ImsRegCallbackHelper: REGISTERING -> REGISTERED
ConnectivityService: ni{MOBILE[LTE] CONNECTED extra: ims}

去电：INVITE -> 183 -> ACTIVE，AMR-WB，RTP 双向
来电：200 OK -> ACK -> re-INVITE 200 -> ACK -> 保持（对方正常 BYE）
音频：setMode before=3 after=3；AudioRecord allZero=false
```

用户实机确认：去电、来电，双方都能听到。

---

## 六、经验教训

1. **AOSP IMS 有三道门**：`android.hardware.telephony.ims` 特性、可绑定的 ImsService、carrier config。缺一门都不行。
2. **LineageOS 官方立场**：IMS 无标准 AOSP 实现，三星这类私有实现设备默认不支持；第三方 PhhIms 是现实路线。
3. **AudioService 的 mode owner 特权优先规则**是隐藏大坑：`setMode` 静默失败，只能靠"特权"破局。
4. **SDP 必须以 CRLF 结尾**，严格 SBC 会直接判 `SDP is illegal`；offer/answer 属性要严格对称（precondition、b=）。
5. **系统 APK 替换后要清 package_cache 并提版本**，否则 PM 用旧解析结果。
6. **XML 文件不要带 BOM**，否则 SystemConfig 解析失败会导致 system_server 起不来。
7. **Android 16 构建的 APK 不能直接跑 A13**（资源表 offset16 格式），必须用目标 SDK 重编。

---

## 七、交付物

| 文件 | 说明 |
|---|---|
| `analysis/phh/PhhIms_a13.apk` | 最终 APK（versionCode 50） |
| `analysis/install_volte.sh` | 一键安装脚本（重刷 ROM 后复用） |
| `analysis/rollback.sh` | 回滚脚本 |
| `analysis/IMS-VoLTE-诊断报告.md` | 完整诊断与三次 SDP 修复记录 |
| `analysis/` 其余 | 探针、构建产物、日志样本 |

---

## 八、已知限制与后续可做

- **无 VoWiFi / 视频通话**（PhhIms 本身不支持）
- **无原生 AEC/降噪**：本次未编 `librnnoise_jni.so` / `libwebrtc_aec_jni.so`（需 NDK），开免提可能有回声
- 音质取决于网络协商（当前可到 AMR-WB）
- 可做：编入 NDK 原生库、打包成 Magisk 模块、把 SDP/权限修复整理成可提交的上游 patch
