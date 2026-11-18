# gracerlte VoLTE

> IMS / VoLTE support for the **Samsung Galaxy Note FE (SM-N935F / `gracerlte`, Exynos 8890)** running **LineageOS 20 (Android 13)**.
>
> Full source, flashable packages, install scripts and troubleshooting docs — including the whole trail from "IMS never registers" to working outgoing/incoming HD calls.

<p align="left">
  <a href="https://github.com/awmc233/gracerlte-volte"><img alt="GitHub" src="https://img.shields.io/badge/GitHub-awmc233%2Fgracerlte--volte-181717?logo=github"></a>
  <a href="https://github.com/awmc233/gracerlte-volte/releases"><img alt="release" src="https://img.shields.io/github/v/release/awmc233/gracerlte-volte"></a>
  <img alt="platform" src="https://img.shields.io/badge/platform-Android%2013-3DDC84">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--2.0-blue">
</p>

[简体中文](README.md) · English

---

## Why this project exists

LineageOS does not support VoLTE on this device out of the box: the ROM ships **no IMS client stack at all**, and the framework logs
`IMS is not supported on this device, skipping ImsResolver.` at boot. LTE data works, but you cannot place calls over LTE.

This project brings in the open-source **PhhIms** stack and then fixes everything else that stood in the way (permissions, audio routing, SDP compatibility).

## Features

- ✅ China Mobile (CMCC) VoLTE: IMS registration, **outgoing calls**, **incoming calls**, **two-way audio**
- ✅ AMR-WB wideband speech (when the network negotiates it)
- ✅ Survives reboots; installable via TWRP or adb
- ✅ Full diagnostic report (PDF) and a project retrospective included
- ✅ MindTheGapps compatibility patch script (no GApps redistribution)

## Requirements

| Item | Requirement |
|---|---|
| Device | SM-N935F (Note FE, `gracerlte`), Exynos 8890 |
| ROM | LineageOS 20.x (Android 13) |
| Carrier | China Mobile CMCC (others untested) |
| Bootloader | Unlocked |
| Recovery | TWRP 3.7.x (optional, needed for zip install) |

> ⚠️ This writes to `/system`. Back up first; reflashing the ROM restores everything.

## Quick start (TWRP)

1. Flash the ROM: `lineage-20.0-*-gracerlte.zip`
2. (Optional) Flash GApps — patch **your own** MindTheGapps package with `tools/patch-mindthegapps.py` first
3. Flash [`twrp/gracerlte-VoLTE-v50-TWRP.zip`](twrp/gracerlte-VoLTE-v50-TWRP.zip)
4. Reboot and wait 10–30 seconds for IMS to register

> Reflashing the ROM overwrites `/system`; simply flash step 3 again afterwards.

## adb install (no TWRP needed)

```bash
# Linux / macOS
adb root
./tools/install-adb.sh

# Windows
tools\install-adb.ps1
```

The script installs the IMS feature declaration, PhhIms, the overlay and the privileged-permission allowlist, sets the VoLTE properties and reboots.

## Verify

```bash
adb shell dumpsys package me.phh.ims | grep versionCode   # versionCode=50
adb shell cmd overlay list | grep me.phh.ims.overlay      # [x] me.phh.ims.overlay
adb shell getprop persist.dbg.volte_avail_ovr             # 1
adb logcat -b all -d | grep -E "IMS registration ready|REGISTERED" | tail -3
```

Expected: `IMS registration ready: REGISTER 200 OK` and `REGISTRATION_STATE_REGISTERED`.
Then place one outgoing and one incoming call to confirm two-way audio.

Or run the bundled checker:

```bash
./tools/verify.sh        # Windows: powershell -ExecutionPolicy Bypass -File tools\verify.ps1
```

## Build

Requirements: **JDK 17** + **Android SDK Platform 33** + **Build-Tools 34** (AGP 8.2).

```bash
cd src
cp local.properties.example local.properties   # point sdk.dir at your SDK
./gradlew assembleDebug
# output: src/app/build/outputs/apk/debug/app-debug.apk
```

- `src/app/libs/android.jar` is a **full AOSP platform jar** (hidden APIs included) and is required to compile;
  the SDK stubs lack classes such as `ImsFeature.CapabilityCallbackProxy`.
- The native AEC/denoise libraries (`jni/`) are not part of this build, so speakerphone may echo.

## Repository layout

```
.
├── README.md                   # Chinese
├── README.en.md                # English (this file)
├── LICENSE                     # GPL-2.0
├── NOTICE.md                   # upstream and third-party notices
├── CHANGELOG.md
├── docs/                       # diagnostic report (PDF/MD) and retrospective
├── prebuilt/                   # built artifacts: PhhIms-50.apk / overlay
├── twrp/                       # TWRP flashable zip
├── tools/                      # adb installers, verify scripts, GApps patcher
└── src/                        # PhhIms fork source (Gradle project)
```

## How it works (short version)

1. Declare `android.hardware.telephony.ims`, so `PhoneFactory` creates an `ImsResolver`
2. Install PhhIms as a priv-app and point `config_ims_mmtel_package` at it via an RRO
3. Grant `MODIFY_PHONE_STATE`, making the app a **privileged mode owner** of AudioService, so
   `MODE_IN_COMMUNICATION` can override the phone process's `MODE_IN_CALL` and the microphone is routed over the AP path
4. Fix the UPDATE / re-INVITE SDP (CRLF, `o=`, bandwidth, precondition) to satisfy strict carrier SBCs

See [`docs/IMS-VoLTE-诊断报告.pdf`](docs/IMS-VoLTE-诊断报告.pdf) for the full story.

## Known limitations

- Only China Mobile has been validated; other carriers may need different SDP/auth handling
- No VoWiFi, no video calling
- No native AEC/denoise, so speakerphone may echo
- Audio quality depends on network negotiation (AMR-WB observed in practice)

## License & credits

Released under **GPL-2.0** (upstream PhhIms is GPL-2.0, and derivative works must use the same license).
See [`NOTICE.md`](NOTICE.md) for upstream and third-party notices.

Special thanks to:

- [phhusson/ims](https://github.com/phhusson/ims) — the original PhhIms implementation
- [Daniel-5352/phhims-exynos8890](https://github.com/Daniel-5352/phhims-exynos8890) — Exynos 8890 port (source baseline of this repository)
- [LineageOS](https://lineageos.org/) — the platform
- [MindTheGapps](https://github.com/MindTheGapps) — the GApps installer (this project only ships a compatibility patch, not its contents)
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — DeepSeek Harness

## Disclaimer

This project modifies the system partition. Bricking, data loss and warranty voiding are all possible.
Back up thoroughly and decide for yourself whether to use it. The author is not liable for any direct or indirect damage.
**GApps are proprietary Google software; this repository does not include or distribute them.**
Modding carries risk — flash at your own risk.
