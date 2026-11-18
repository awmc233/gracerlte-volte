# NOTICE — 上游来源与第三方声明

本仓库包含或派生自以下项目。分发时请保留本文件与 `LICENSE`。

## 1. PhhIms（原始实现）

- 项目：https://github.com/phhusson/ims
- 作者：phhusson 及贡献者
- 许可证：**GPL-2.0**
- 用途：开源 IMS/VoLTE 实现，本项目的基础

## 2. phhims-exynos8890（源码基线）

- 项目：https://github.com/Daniel-5352/phhims-exynos8890
- 作者：Daniel-5352 及贡献者
- 许可证：**GPL-2.0**（仓库内 `LICENSE` 原文）
- 用途：面向 Samsung Exynos 8890（S7 / S7 edge / Note FE）的适配 fork
- 说明：`src/` 目录即基于该 fork 的修改版本，主要改动见 `CHANGELOG.md`

## 3. LineageOS

- 项目：https://github.com/LineageOS
- 许可证：Apache-2.0（平台代码）
- 用途：目标系统平台；本仓库**不包含** LineageOS 的任何二进制或源码

## 4. MindTheGapps

- 项目：https://github.com/MindTheGapps
- 用途：Google 应用安装器
- **重要**：本仓库**不包含、不分发** MindTheGapps 或其内的任何 Google 应用（GmsCore、Play Store 等均为 Google 专有软件）。
  `tools/patch-mindthegapps.py` 只对**用户自行获取**的安装包做 `update-binary` 兼容性修补，不改变其内容归属。

## 5. Android SDK Platform-Tools（adb）

- 项目：https://developer.android.com/studio/releases/platform-tools
- 许可证：Apache-2.0
- 说明：本仓库**不包含** adb 二进制，使用时请自行安装。

## 6. Samsung 专有组件

本仓库**不包含**任何 Samsung 的 vendor blob、固件或私有库。所有与设备相关的路径/分区名仅作为脚本参数出现。

## 7. 文档

`docs/` 下的诊断报告与项目总结由本项目作者撰写，采用 **CC BY 4.0** 许可（代码部分仍为 GPL-2.0）。
