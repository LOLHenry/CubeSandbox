# AGR Mobile 实测报告索引

本目录按**时间顺序**收录对腾讯云 AGR Mobile 沙箱的实测报告。文件名格式：

```
{序号}-{YYYYMMDD}-{主题}.md
```

| 序号 | 含义 |
|------|------|
| `01` | 首轮 broad 探测（硬件 mock、android-world、底座指纹） |
| `02` | 第二轮架构深挖（sidecar 层、HTTPS 数据面、envd 暴露性） |
| `03` | E2B SDK envd 语义验证（`commands.run` / `files.write` 定论） |
| `04` | E2B SDK envd 进程可观测性（`get_info` / `is_running` / `ps` 等） |
| `05` | Sidecar OCI 打包、PID 层级、网络与复刻实施（推断 + 源码） |
| `06` | Mobile 冷启动时延基准（控制面 + 数据面探活，5 次批量） |

产物目录与报告序号对齐：`probe/artifacts/{序号}-{YYYYMMDD}-{地域}/`；性能探测见 `probe/artifacts/coldstart-*`。

---

## 报告时间线

| 序号 | 文件 | 日期 | 存放位置 | 范围 |
|------|------|------|----------|------|
| **01** | [`01-20260723-mobile-hardware-mock.md`](01-20260723-mobile-hardware-mock.md) | 2026-07-23 | 外部仓库 [LOLHenry/android-cuttlefish](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md) | mobile + android-world 底座指纹；WiFi/GPS/BT/Camera 硬件面探测 |
| **02** | [`02-20260824-mobile-architecture.md`](02-20260824-mobile-architecture.md) | 2026-08-24 | **本仓库** | mobile 架构分层（sidecar vs Android）；HTTPS 数据面；envd 暴露性修正 |
| **03** | [`03-20260824-e2b-envd-semantics.md`](03-20260824-e2b-envd-semantics.md) | 2026-08-24 | **本仓库** | E2B SDK envd 语义：**不可用**（无隐藏通道） |
| **04** | [`04-20260824-e2b-envd-process.md`](04-20260824-e2b-envd-process.md) | 2026-08-24 | **本仓库** | E2B SDK **无法观测 envd 进程**；`envd_version` 仅为控制面元数据 |
| **05** | [`05-20260824-sidecar-oci-and-pid-hierarchy.md`](05-20260824-sidecar-oci-and-pid-hierarchy.md) | 2026-08-24 | **本仓库** | Sidecar OCI 多容器打包推测；PID 层级；eth0/netns；鲲鹏复刻路线 |
| **06** | [`06-20260824-mobile-coldstart-bench.md`](06-20260824-mobile-coldstart-bench.md) | 2026-08-24 | **本仓库** | Mobile 冷启动时延（5 次批量）；脚本 + JSON 产物 |

**结论总索引：** [`../FINDINGS.md`](../FINDINGS.md)（按主题查结论 → 报告 → 原始产物）

### 阅读建议

1. **先读 01**：建立「Cube VM + Redroid/SmartRun Android 14」底座认知，了解硬件 mock 边界。
2. **再读 02**：在 01 基础上补全 sidecar 层、三条数据通路、端口进程归属；**以 02 为准**修正 01 中关于 envd `:49983` 的表述。
3. **读 03**：用 E2B SDK 最终定论 — mobile **不提供** `commands.run` / `files.write` 等 envd 语义。
4. **读 04**：扩展 SDK 接口 — **仍无法判断 envd 进程是否存在**。
5. **读 05**：Sidecar OCI 打包、PID 层级、网络命名空间、鲲鹏复刻实施路线。
6. **读 06**：冷启动时延基准（控制面 ~2s RUNNING；Appium ~5s；ADB/e2e 波动大）。
7. **查索引**：[`FINDINGS.md`](../FINDINGS.md) 按主题定位结论与证据文件。

### 02 对 01 的主要修正

| 项 | 01（2026-07-23） | 02（2026-08-24） |
|----|------------------|------------------|
| `:49983` envd | 列为实例内端口 | ❌ mobile 类型**未向数据面暴露**（网关 `310508`） |
| Appium `:4723` | 实例内监听 | ✅ 确认为 **Linux sidecar**（Node.js），非 Android 进程 |
| `:8000` / `:8886` | 均标为 scrcpy 相关 | ✅ 分层：8000=sidecar Web，8886=Android scrcpy-server |
| 架构图 | 单层「进程: adbd, Appium, envd, scrcpy」 | ✅ 分为 **Sidecar 层 + Android 层** |

### 03 对 02 的补充（定论）

| 项 | 02（curl/ADB） | 03（E2B SDK） |
|----|----------------|---------------|
| envd 是否隐藏可用 | 推断「未暴露」 | ✅ **SDK 直接报错 310508，无隐藏通道** |
| `commands.run` | 未测 | ❌ 不可用 |
| `files.write` | 未测 | ❌ 不可用 |
| 同实例 Appium | ✅ HTTPS 200 | ✅ 对照实验仍 200 |

### 04 对 03 的补充（进程视角）

| 项 | 03 | 04 |
|----|-----|-----|
| `get_info().envd_version` | 未强调 | ✅ 返回 `0.2.10`（**控制面元数据，非进程证明**） |
| `is_running()` / `:49983/health` | 未单独测 | ❌ `310508` |
| `commands.run("ps…envd")` | 未测 | ❌ `310508`，**无法列 envd 进程** |
| `pty.create()` | 未测 | ❌ `310508` |
| 能否判断 envd 进程存在 | 语义不可用 | **SDK 无观测能力**（与 02 ADB 侧「无 envd 进程」一致） |

### 05 归档（架构推断与补充）

| 主题 | 主要文档 | 证据类型 |
|------|----------|----------|
| Android PID 1 = init，≠ sidecar | 05 §1；02 §PID 视角 | ✅ ADB 实测 |
| PID 1 不独占 eth0；共享 netns | 05 §2；02 §Sidecar | ✅ netstat/ns 实测 |
| VM PID 1 = cube-agent | 05 §3 | ✅ `agent/README.md` |
| Sidecar 独立 OCI + 多容器 cubebox | 05 §4 | ⚠️ 推断 + 挂载标记 |
| 鲲鹏复刻路线 A/B | 05 §6；`OPTIONAL_COMPONENTS.md` | 设计文档 |

---

## 相关文档（非探测报告）

| 文件 | 用途 |
|------|------|
| [`FINDINGS.md`](../FINDINGS.md) | **结论总索引**（主题 → 报告 → 原始产物） |
| [`../AGR_REFERENCE.md`](../AGR_REFERENCE.md) | 操作速查（凭据、端口、SDK 示例）；汇总最新结论 |
| [`../OPTIONAL_COMPONENTS.md`](../OPTIONAL_COMPONENTS.md) | 鲲鹏复刻可选组件（Appium/scrcpy） |
| [`../OFFLINE_KUNPENG.md`](../OFFLINE_KUNPENG.md) | 鲲鹏离线部署指南 |
| [`OFFICIAL_MULTI_CONTAINER.md`](../OFFICIAL_MULTI_CONTAINER.md) | AGR 官方多容器支持边界与自建 Cube 操作步骤 |
| [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) | AGR 官方 vs CubeSandbox 鲲鹏复刻对照 |
