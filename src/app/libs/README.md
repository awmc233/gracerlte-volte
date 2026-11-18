# app/libs

编译 PhhIms 需要以下两个 jar：

| 文件 | 说明 |
|---|---|
| `android.jar`（约 53 MB） | **AOSP 完整平台 jar**（包含隐藏 API）。Android SDK 自带的 `platforms/android-33/android.jar` 是精简 stub，缺少 `ImsFeature.CapabilityCallbackProxy` 等类，无法编译本项目。 |
| `ImsMediaFramework.jar` | IMS 媒体相关的补充接口。 |

`android.jar` 已随仓库提供，可直接构建。
如需替换，请使用与设备系统同版本（Android 13 / API 33）的 **platform** jar，
并保持文件名不变。
