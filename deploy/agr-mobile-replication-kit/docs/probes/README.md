# AGR Mobile 实测报告索引

本目录按**时间顺序**收录对腾讯云 AGR Mobile 沙箱的实测报告。文件名格式：

```
{序号}-{YYYYMMDD}-{主题}.md
```

| 序号 | 含义 |
|------|------|
| `01` | 首轮 broad 探测（硬件 mock、android-world、底座指纹） |
| `02` | 第二轮架构深挖（sidecar 层、HTTPS 数据面、envd 暴露性） |

产物目录与报告序号对齐：`probe/artifacts/{序号}-{YYYYMMDD}-{地域}/`。

---

## 报告时间线

| 序号 | 文件 | 日期 | 存放位置 | 范围 |
|------|------|------|----------|------|
| **01** | [`01-20260723-mobile-hardware-mock.md`](01-20260723-mobile-hardware-mock.md) | 2026-07-23 | 外部仓库 [LOLHenry/android-cuttlefish](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md) | mobile + android-world 底座指纹；WiFi/GPS/BT/Camera 硬件面探测 |
| **02** | [`02-20260824-mobile-architecture.md`](02-20260824-mobile-architecture.md) | 2026-08-24 | **本仓库** | mobile 架构分层（sidecar vs Android）；HTTPS 数据面；envd 暴露性修正 |

### 阅读建议

1. **先读 01**：建立「Cube VM + Redroid/SmartRun Android 14」底座认知，了解硬件 mock 边界。
2. **再读 02**：在 01 基础上补全 sidecar 层、三条数据通路、端口进程归属；**以 02 为准**修正 01 中关于 envd `:49983` 的表述。
3. **读 03**：用 E2B SDK 最终定论 — mobile **不提供** `commands.run` / `files.write` 等 envd 语义。

### 02 对 01 的主要修正

| 项 | 01（2026-07-23） | 02（2026-08-24） |
|----|------------------|------------------|
| `:49983` envd | 列为实例内端口 | ❌ mobile 类型**未向数据面暴露**（网关 `310508`） |
| Appium `:4723` | 实例内监听 | ✅ 确认为 **Linux sidecar**（Node.js），非 Android 进程 |
| `:8000` / `:8886` | 均标为 scrcpy 相关 | ✅ 分层：8000=sidecar Web，8886=Android scrcpy-server |
| 架构图 | 单层「进程: adbd, Appium, envd, scrcpy」 | ✅ 分为 **Sidecar 层 + Android 层** |

---

## 相关文档（非探测报告）

| 文件 | 用途 |
|------|------|
| [`../AGR_REFERENCE.md`](../AGR_REFERENCE.md) | 操作速查（凭据、端口、SDK 示例）；汇总最新结论 |
| [`../OPTIONAL_COMPONENTS.md`](../OPTIONAL_COMPONENTS.md) | 鲲鹏复刻可选组件（Appium/scrcpy） |
| [`../OFFLINE_KUNPENG.md`](../OFFLINE_KUNPENG.md) | 鲲鹏离线部署指南 |
| [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) | AGR 官方 vs CubeSandbox 鲲鹏复刻对照 |
