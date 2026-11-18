# gracerlte VoLTE

> 给 **Samsung Galaxy Note FE（SM-N935F / `gracerlte`，Exynos 8890）** 的 **LineageOS 20（Android 13）** 补齐 IMS / VoLTE 支持。
>
> 完整的源码、可刷包、安装脚本与排障文档——包含从"IMS 完全不注册"到"去电/来电双向高清通话"的全部修复过程。

<p align="left">
  <a href="https://github.com/awmc233/gracerlte-volte"><img alt="GitHub" src="https://img.shields.io/badge/GitHub-awmc233%2Fgracerlte--volte-181717?logo=github"></a>
  <a href="https://github.com/awmc233/gracerlte-volte/releases"><img alt="release" src="https://img.shields.io/github/v/release/awmc233/gracerlte-volte"></a>
  <img alt="platform" src="https://img.shields.io/badge/platform-Android%2013-3DDC84">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--2.0-blue">
</p>

简体中文 · [English](README.en.md)

---

## 为什么需要这个项目

LineageOS 官方不支持这台机器的 VoLTE：ROM 里**没有任何 IMS 客户端栈**，开机时框架直接打印
`IMS is not supported on this device, skipping ImsResolver.`，因此 4G 数据正常、但无法用 LTE 打电话。

本项目用开源 **PhhIms** 补齐了 IMS 栈，并解决了信号之外的一系列问题（权限、音频路由、SDP 兼容性）。

## 特性

- ✅ 中国移动 VoLTE：IMS 注册、**去电**、**来电**、**双向音频**
- ✅ AMR-WB 高清语音（网络协商支持时）
- ✅ 重启保持；TWRP 卡刷 / adb 两种安装方式
- ✅ 附带完整诊断报告（PDF）与项目复盘
- ✅ 附带 MindTheGapps 兼容性修复脚本（不重分发 GApps）

## 适用条件

| 项目 | 要求 |
|---|---|
| 机型 | SM-N935F（Note FE，`gracerlte`），Exynos 8890 |
| 系统 | LineageOS 20.x（Android 13） |
| 运营商 | 中国移动 CMCC（其它运营商未验证） |
| Bootloader | 已解锁 |
| Recovery | TWRP 3.7.x（可选，卡刷需要） |

> ⚠️ 会写入 `/system`，请先备份。改错可重刷 ROM 恢复。

## 快速开始（TWRP 卡刷）

1. 刷入 ROM：`lineage-20.0-*-gracerlte.zip`
2. （可选）刷 GApps —— 用 `tools/patch-mindthegapps.py` 修补**你自己的** MindTheGapps 包后再刷
3. 刷 [`twrp/gracerlte-VoLTE-v50-TWRP.zip`](twrp/gracerlte-VoLTE-v50-TWRP.zip)
4. 重启，等待 10–30 秒让 IMS 注册

> 重刷 ROM 会覆盖 `/system`，之后重新刷一次第 3 步即可。

## adb 安装（无需 TWRP）

```bash
# Linux / macOS
adb root
./tools/install-adb.sh

# Windows
tools\install-adb.ps1
```

脚本会写入 IMS 特性声明、PhhIms、overlay 与权限白名单，设置 VoLTE 属性并重启。

## 验证

```bash
adb shell dumpsys package me.phh.ims | grep versionCode   # versionCode=50
adb shell cmd overlay list | grep me.phh.ims.overlay      # [x] me.phh.ims.overlay
adb shell getprop persist.dbg.volte_avail_ovr             # 1
adb logcat -b all -d | grep -E "IMS registration ready|REGISTERED" | tail -3
```

期望看到 `IMS registration ready: REGISTER 200 OK` 与 `REGISTRATION_STATE_REGISTERED`。
然后拨测一通去电与来电，确认双向音频。

也可以直接跑校验脚本（自动逐项检查并给结论）：

```bash
./tools/verify.sh
# Windows:
powershell -ExecutionPolicy Bypass -File tools\verify.ps1
```


## 构建

环境：**JDK 17** + **Android SDK Platform 33** + **Build-Tools 34**（AGP 8.2 要求）。

```bash
cd src
cp local.properties.example local.properties   # 指向你的 SDK
./gradlew assembleDebug
# 产物：src/app/build/outputs/apk/debug/app-debug.apk
```

- `src/app/libs/android.jar` 是 AOSP **完整平台 jar**（含隐藏 API），编译必需；可用你自己的同版本 jar 替换。
- 原生 AEC/降噪库（`jni/`）未包含在构建中，因此免提可能有回声。

## 仓库结构

```
.
├── README.md
├── LICENSE                     # GPL-2.0
├── NOTICE.md                   # 上游来源与第三方声明
├── CHANGELOG.md
├── docs/                       # 诊断报告（PDF/MD）与项目复盘
├── prebuilt/                   # 构建成品：PhhIms-50.apk / overlay
├── twrp/                       # 卡刷包
├── tools/                      # adb 安装脚本、GApps 修补脚本
└── src/                        # PhhIms fork 源码（Gradle 工程）
```

## 工作原理（简述）

1. 补 `android.hardware.telephony.ims` 特性，让 `PhoneFactory` 创建 `ImsResolver`
2. 以 priv-app 方式安装 PhhIms，并用 RRO 把 `config_ims_mmtel_package` 指向它
3. 授予 `MODIFY_PHONE_STATE`，让应用成为 AudioService 的**特权 mode owner**，`MODE_IN_COMMUNICATION` 才能压过电话进程的 `MODE_IN_CALL`，麦克风走 AP 通路
4. 修正 UPDATE / re-INVITE 的 SDP（CRLF、`o=`、带宽、precondition），适配严格的运营商 SBC

详细过程见 [`docs/IMS-VoLTE-诊断报告.pdf`](docs/IMS-VoLTE-诊断报告.pdf)。

## 已知限制

- 仅验证中国移动；其它运营商的 SDP/鉴权可能不同
- 不支持 VoWiFi、视频通话
- 未编译原生 AEC/降噪，免提可能有回声
- 音质取决于网络协商（实测可达 AMR-WB）

## 许可证与致谢

本项目基于 **GPL-2.0** 发布（上游 PhhIms 为 GPL-2.0，衍生作品必须同协议）。
上游来源与第三方组件声明见 [`NOTICE.md`](NOTICE.md)。

特别感谢：

- [phhusson/ims](https://github.com/phhusson/ims) —— PhhIms 原始实现
- [Daniel-5352/phhims-exynos8890](https://github.com/Daniel-5352/phhims-exynos8890) —— Exynos 8890 适配 fork（本仓库的源码基线）
- [LineageOS](https://lineageos.org/) —— 系统平台
- [MindTheGapps](https://github.com/MindTheGapps) —— GApps 安装器（本项目仅提供兼容性补丁，不包含其内容）
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) —— DeepSeek Harness（没有dsh就不会有这些东西，毕竟我水平还仅仅入门级）
## 免责声明

本项目修改系统分区，存在变砖、数据丢失、保修失效等风险。请在充分备份后自行决定是否使用。
作者不对任何直接或间接损失负责。**GApps 属于 Google 专有软件，本仓库不包含、也不分发。**
内容仅供参考，内容供应者不会就任何资料不准，错漏，延误或阻碍所引起的损失承担任何形式的责任！！！！
折腾有风险，刷机请谨慎！！！！！！！！！！
