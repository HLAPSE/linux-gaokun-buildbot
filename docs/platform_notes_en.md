# Platform Notes: Device Variants & Capability Boundaries

Device identification and hardware capability-boundary conclusions for the MateBook E Go family.
The in-depth forensics are not repeated here; each item links to the corresponding document in
[aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun).

## Device identification

MateBook E Go machines based on the Snapdragon 8cx Gen 3 (`SC8280XP`) share the `gaokun3`
device tree and come in two variants:

| Variant | Prime core max frequency | Supported by these images |
|---------|--------------------------|:---:|
| **2022 Performance Edition** (GK-W76) | 3.0 GHz | ✅ verified on device |
| **2023 Edition** (downclocked) | ~2.69 GHz | ✅ runs; different clocks/thermal design |
| 2022 LTE Edition | — (`SC8180X` / `gaokun2`) | ❌ device tree and patches are incompatible |

**The model string alone is not a reliable identifier**: the device tree `model` only says
`Matebook E Go`, and the DMI `product_name` always reads `GK-W7X` (not the `GK-W76` used on
shopping pages). Use the following three checks instead:

```bash
# ① Device tree compatible (rules out the LTE edition)
tr -d '\0' < /proc/device-tree/compatible
#   gaokun3 machines: huawei,gaokun3 qcom,sc8280xp
#   LTE edition: gaokun2 / sc8180x

# ② Prime core max frequency (tells the 2022 Performance from the 2023 Edition)
cat /sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq
#   2995200     → 3.0 GHz   → 2022 Performance Edition
#   ~2690000    → 2.69 GHz  → 2023 Edition

# ③ Built-in panel
tr '\0' ' ' < /proc/device-tree/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible
#   expected: csot,ppc357db1-4 himax,hx83121a
```

`gaokun-check` prints these checks and the resulting verdict automatically — attach its output
when filing issues.

## Capability boundaries (verified conclusions)

| Hardware | Conclusion |
|----------|------------|
| **Fingerprint** | The FocalTech FTE7001 sits on an SPI bus exclusively owned by the Qualcomm secure world (QTEE); the non-secure side only gets a GPIO interrupt, and capture/matching runs inside a signed trustlet — **unreachable via a regular Linux driver**. Forensics: easy-for-gaokun [`docs/fingerprint.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/fingerprint.md) |
| **Stylus** | No pen channel has ever been implemented on Linux (the driver declares neither `BTN_TOOL_PEN` nor `ABS_PRESSURE`) |
| **Auto-rotation** | The device tree has no accelerometer node — impossible at the hardware level |
| **EL2 (KVM) ↔ video hard-decode** | Mutually exclusive. The video subsystem's secure-world support (CP memory protection, state machine) sits behind QTEE + signed TAs; the IRIS/EL2 route was abandoned, while EL1 + venus hard-decode works. This project's **EL2 variant has no video hard-decode either**. Forensics: easy-for-gaokun [`docs/video-decode.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/video-decode.md) |
| **Speaker tuning** | The kernel clamps the PA volume at 0 dB (no active speaker protection; do not raise it); the Windows-side Histen per-model tuning and four-speaker spatial audio have no Linux equivalent |

## Known shared issues

- `qcom-apm gprsvc CMD timeout` early at boot: caused by a soundwire port-count mismatch; the
  sound card still registers and there is no known practical impact so far.
- `gaokun-ec` fails to create a device link with the USB controller: harmless warning.
- The RTC reads a wrong time at boot until NTP corrects it.
- Touch idle power: host-side interrupts can be reduced by the driver's idle policy, but the IC
  itself keeps scanning at 120 Hz; going lower needs AFE deep sleep + blind wake at the cost of
  a 30–50 ms first-touch latency (see easy-for-gaokun [`docs/touch-idle-policy.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/touch-idle-policy.md)).

## Credits

The fingerprint, video-decode, touch-idle and audio conclusions come from the on-device
forensics in [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun); the
touchscreen interface-mode fix (`0100`), the SPI GSI patches (`others/0008`, `others/0009`),
the GPU telemetry patch (`others/0010`) and the touch benchmark tool (`tools/touch-bench/`)
were introduced into this project from that repository.
