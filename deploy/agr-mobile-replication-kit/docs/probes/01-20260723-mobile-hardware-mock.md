# 探测 01 — AGR Mobile / Android World 硬件与底座（2026-07-23）

> **序号 01 / 共 02** · 本文件为索引页；完整正文在外部仓库。  
> 后续报告：[`02-20260824-mobile-architecture.md`](02-20260824-mobile-architecture.md)

## 元数据

| 项 | 值 |
|----|-----|
| 探测序号 | **01** |
| 日期 | 2026-07-23 |
| 地域 | `ap-shanghai` |
| 存放 | 外部 — 非本仓库正文 |
| 完整报告 | [LOLHenry/android-cuttlefish — tencent-agent-runtime-mobile-hardware-mock.md](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md) |

## 探测范围

- Tool 类型：`mobile`、`android-world`
- 方法：`agr` CLI + `agr instance mobile adb` + `getprop` / `dumpsys` / 硬件注入尝试
- 重点：底座是否为 Emulator / Cuttlefish / Redroid；WiFi、GNSS、BT、Camera、Sensor 是否有官方 mock API

## 核心结论（摘要）

1. 底座为 **Cube Hypervisor MicroVM + SmartRun/ReDroid Android 14 x86_64**，非 Cuttlefish、非经典 AVD。
2. 官方控制面：**Appium + ADB + scrcpy**；`agr instance mobile` 无硬件 mock 子命令。
3. android-world ≈ mobile 底座 + SmartRun `android_world_adapt` v23。
4. 端口观察（当时）：5555 adbd、4723 Appium、8000/8886 scrcpy、**49983 envd（后在 02 中修正）**。

## 与探测 02 的关系

| 01 建立的事实 | 02 的延伸 |
|---------------|-----------|
| Redroid/SmartRun 底座 | 补充 Linux **sidecar 层**与 Android 层分工 |
| 端口列表（netstat） | 补充 HTTPS 数据面鉴权、进程归属、inode 映射 |
| envd `:49983` 在端口表 | **02 修正**：mobile 类型网关未配置该端点 |

请结合 [`README.md`](README.md) 时间线阅读；架构与端口以 **02** 为准。
