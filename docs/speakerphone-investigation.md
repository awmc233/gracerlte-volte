# 免提（speakerphone）问题调查记录

> 设备：SM-N935F / `gracerlte`，LineageOS 20（Android 13，userdebug）
> 时间：2026-11-19
> 结论：**在公开源码范围内无法修复**，属于三星音频 HAL 的限制。

## 现象

VoLTE 通话中按免提按钮：

- 按钮图标会正常亮起/熄灭，通话音量略有变化
- 但实际声音始终从听筒输出，扬声器不出声

## 根因

三星音频 HAL 对"通话"分两套通路：

| 概念 | 判定 | 路由 |
|---|---|---|
| CP 通话 | `amode == MODE_IN_CALL` | 设备变化时调用 `voice_set_path()` → `SitRilSetVoicePath()` → 应用 `voice-*-wb` mixer path（`voice-speaker-wb` 就是这条） |
| AP 通话 | `amode == MODE_IN_COMMUNICATION` | `update_call_stream()` → `adev_set_route()` → `proxy_set_route()` → **闭源 ABOX 代理** |

而 VoLTE 场景有一个硬性冲突：

- 只有 `MODE_IN_CALL` 才会让 HAL 切 `voice-speaker-wb`（免提出声）
- 但 `MODE_IN_CALL` 会让 HAL 把采集路由到 modem（`AudioRecord` 全零，对方听不到）
- 要让麦克风走 AP 通路，PhhIms 必须保持 `MODE_IN_COMMUNICATION`（mode owner）

因此 **"免提出声"和"麦克风可用"在 HAL 层互斥**。

## 实测证据

### 1. 框架层已经正确

```
PHH AudioRoute: Track route: voice=2 media=2 active=true communication=2
                speakerphone=true mediaVolume=25 telecom=SPEAKER
dumpsys media.audio_policy: Strategy(15)/Strategy(18) = AUDIO_DEVICE_OUT_SPEAKER
dumpsys media.audio_flinger: Output devices: 0x2 (AUDIO_DEVICE_OUT_SPEAKER)
```

### 2. HAL 层没有切换

```
audio_route: Apply path: voice-earpiece-wb
audio_route: Apply path: voice-earpiece-mic-wb
（整个通话期间没有任何 voice-speaker-wb，也没有 media 的 speaker path）
```

### 3. 模式对比实验

| 音频模式 | 麦克风 `AudioRecord` | HAL path |
|---|---|---|
| `MODE_IN_COMMUNICATION`（应用持有） | `allZero=false` ✅ | 始终 `voice-earpiece-wb` ❌ |
| `MODE_IN_CALL`（Telecom 持有） | `allZero=true` ❌ | 切到 `voice-speaker-wb` ✅ |

## 试过的两条路线

### A. 应用侧（下行改用 `STREAM_MUSIC`）

免提时创建 `STREAM_MUSIC` 轨并切换播放（`SipAudioRouteBridge` + trackProvider）。

结果：媒体轨创建成功、`active=true`、媒体音量 25、麦克风正常，但 HAL 仍只有
`voice-earpiece-wb`——主输出被锁在通话路径，媒体播放共用同一输出，依旧从听筒出声。

### B. ROM 侧（system-uid helper 设置 `FOR_COMMUNICATION` force-use）

以 `user system` 运行 `app_process` 助手，轮询 `IAudioService` 并调用
`AudioSystem.setForceUse(FOR_COMMUNICATION, FORCE_SPEAKER)`。

结果：`rc=0`、`Force use for communications: 1` 设置成功，但 HAL 在
`MODE_IN_COMMUNICATION` 下根本不读这个值；只有在 `MODE_IN_CALL` 下才生效（而那时麦克风已失效）。

## HAL 源码依据

- 仓库：<https://github.com/8890q/android_hardware_samsung_slsi-linaro_exynos>（`lineage-20`）
- 文件：`libaudio/audiohal/audio_hw.c`、`voice_manager.c`

关键逻辑：

```c
static bool isCPCallMode(struct audio_device *adev) {
    return adev->amode == AUDIO_MODE_IN_CALL;
}
```

```c
/* out_set_parameters: 只有 CP 通话才更新 RIL 语音路径 */
if (output_drives_call(adev, out) && isCPCallMode(adev)) {
    voice_set_path(adev->voice, out->common.requested_devices);
    ...
}
```

```c
/* adev_set_mode: HAL 会强行把 IN_COMMUNICATION 拉回 IN_CALL */
if ((mode == AUDIO_MODE_IN_COMMUNICATION) && isCPCallMode(adev) && adev->voice->realcall) {
    mode = adev->amode;   // AUDIO_MODE_IN_CALL
    adev->voice->keep_call_mode = true;
}
```

ROM 信息来源（作者 Ivan Meler）：

- 设备树：<https://github.com/8890q/android_device_samsung_gracerlte>（`lineage-20.0`）
- 更新日志：<https://ivanmeler.github.io/changes/gracerlte-20.html>

## 复现方法

1. 拨号，接通后按免提
2. 观察日志：
   ```bash
   adb logcat -b all -d | grep -E "Apply path|Track route|AudioRecord.read"
   adb shell dumpsys media.audio_policy | grep -E "Strategy\(1[58]\)|Force use for comm"
   ```
3. 现象：策略/设备/轨道都显示 speaker，HAL 仍 `voice-earpiece-wb`，采集 `allZero=false`

## 后续可能方向（均需更深的厂商层工作）

1. 分析闭源 ABOX 音频代理（`libsitril` / `audio_proxy`），找到 AP 通话扬声器路由的 mixer 控制
2. 自建 mixer 写入工具（类似 tinymix），由 system helper 直接写 ALSA 控件
3. 修改 `audio_hw.c` 让 AP 通话也调用 `voice_set_path()` 并保持 AP 采集，
   需要完整 LineageOS 构建环境

