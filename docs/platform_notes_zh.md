# 平台说明：机型鉴别与能力边界

面向 MateBook E Go 系列用户与贡献者的机型鉴别方法和硬件能力边界结论。
深度取证过程不在本文展开，均指向 [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun) 的对应文档。

## 机型鉴别

MateBook E Go 基于骁龙 8cx Gen 3（`SC8280XP`）的机器共用 `gaokun3` 设备树，分两个变体：

| 变体 | 大核最高频率 | 本镜像支持 |
|------|-------------|:---:|
| **2022 性能版**（GK-W76） | 3.0 GHz | ✅ 实测机型 |
| **2023 版**（降频） | 约 2.69 GHz | ✅ 可运行，频率/热设计不同 |
| 2022 LTE 版 | —（`SC8180X` / `gaokun2`） | ❌ 设备树与补丁完全不通用 |

**型号字符串本身不是可靠判据**：设备树 `model` 只报 `Matebook E Go`，DMI `product_name` 一律报
`GK-W7X`（并非电商页引用的 `GK-W76`），区分变体请用以下三条判据：

```bash
# ① 设备树 compatible（区分 LTE 版）
tr -d '\0' < /proc/device-tree/compatible
#   gaokun3 机型应为: huawei,gaokun3 qcom,sc8280xp
#   LTE 版为 gaokun2 / sc8180x

# ② 大核最高频率（区分 2022 性能版与 2023 降频版）
cat /sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq
#   2995200     → 3.0 GHz   → 2022 性能版
#   约 2690000  → 2.69 GHz  → 2023 版

# ③ 内屏面板
tr '\0' ' ' < /proc/device-tree/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible
#   应为: csot,ppc357db1-4 himax,hx83121a
```

`gaokun-check` 会自动输出以上判据与判定结果，提 issue 时请附上。

## 能力边界（实测结论）

| 硬件 | 结论 |
|------|------|
| **指纹** | FocalTech FTE7001 挂在 SPI 上，但该 SPI 由高通安全世界（QTEE）独占，非安全侧只有一个 GPIO 中断连接，取图/比对全部在签名 trustlet 内完成——**Linux 常规驱动路线不可达**。取证见 easy-for-gaokun [`docs/fingerprint.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/fingerprint.md) |
| **手写笔** | Linux 侧从未实现笔通道（驱动不声明 `BTN_TOOL_PEN` / `ABS_PRESSURE`） |
| **自动旋转** | 设备树没有加速度计节点，硬件层面不可能实现 |
| **EL2(KVM) ↔ 视频硬解** | 互斥。视频子系统安全世界支持（CP 内存保护、状态机）在 QTEE + 签名 TA 之后，IRIS/EL2 路线已放弃；EL1 + venus 硬解可用。本项目 **EL2 变体同样没有视频硬解**。取证见 easy-for-gaokun [`docs/video-decode.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/video-decode.md) |
| **扬声器调音** | 内核把功放增益限幅在 0 dB（无主动扬声器保护，不可放宽）；Windows 侧 Histen 逐机型调音与四扬声器空间音效在 Linux 无对应实现 |

## 已知共性问题

- 开机初期 `qcom-apm gprsvc CMD timeout`：soundwire 端口数不匹配所致，声卡仍能正常注册，暂无实际影响。
- `gaokun-ec` 无法与 USB 控制器建立 device link：无害告警。
- RTC 开机时间错误，联网后由 NTP 纠正。
- 触屏空闲功耗：主机侧中断可由驱动空闲策略压低，但 IC 自身仍以 120 Hz 扫描；进一步降低需 AFE 深睡 + 盲唤醒，代价是 30–50 ms 首触延迟（见 easy-for-gaokun [`docs/touch-idle-policy.md`](https://github.com/aoripus/easy-for-gaokun/blob/main/docs/touch-idle-policy.md)）。

## 致谢

本文的指纹、视频硬解、触屏功耗与音频结论均来自 [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun)
在 2022 性能版实机上的取证工作；触屏接口模式修复（`0100`）、SPI GSI 补丁（`others/0008`、`others/0009`）、
GPU 遥测补丁（`others/0010`）与触屏基准工具（`tools/touch-bench/`）也由该仓库引入本项目。
