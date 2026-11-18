# tools

| 文件 | 说明 |
|---|---|
| `install-adb.sh` / `install-adb.ps1` | 通过 adb（需 `adb root`）安装 VoLTE 组件，自动重启并验证 |
| `device-install.sh` / `device-uninstall.sh` | 设备端执行脚本，由上面的安装器推送 |
| `patch-mindthegapps.py` | 修补**你自己的** MindTheGapps zip，使其能在本机 TWRP 下刷入 |

## adb 安装

```bash
adb root
./install-adb.sh
```

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-adb.ps1
```

## 修补 MindTheGapps

```bash
python3 patch-mindthegapps.py MindTheGapps-13.0.0-arm64-*.zip MindTheGapps-fixed.zip
```

然后把 `MindTheGapps-fixed.zip` 放进手机，用 TWRP 刷入。

补丁只改 `META-INF/com/google/android/update-binary`：

1. 按挂载点匹配 `/etc/recovery.fstab`，并返回行内第一个 `/dev/*` 字段（修复找不到 SYSTEM 分区）
2. `ro.bionic.arch` 为空时默认取包内架构（TWRP 未定义该属性）

> 修补后 zip 的 JAR 签名失效。TWRP 默认不校验 zip 签名，直接刷即可；
> 若开启了「Zip signature verification」，请先关闭。
>
> 本脚本不包含、不修改任何 Google 应用；请自行从官方渠道获取 MindTheGapps。
