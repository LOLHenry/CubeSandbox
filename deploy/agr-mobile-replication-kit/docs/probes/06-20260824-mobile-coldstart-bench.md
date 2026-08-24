# 探测 06 — AGR Mobile 冷启动时延基准（2026-08-24）

> **序号 06** · 性能探测（非架构）  
> 索引：[`../FINDINGS.md`](../FINDINGS.md) · 脚本：[`../../probe/agr-mobile-coldstart-bench.py`](../../probe/agr-mobile-coldstart-bench.py)  
> 原始产物：[`../../probe/artifacts/coldstart-20260824-ap-shanghai/README.md`](../../probe/artifacts/coldstart-20260824-ap-shanghai/README.md)

## 探测概要

| 项 | 值 |
|----|-----|
| 日期 | 2026-08-24 |
| 地域 | `ap-shanghai` |
| Tool | `sdt-g9nj2vc4`（`ToolType=mobile`） |
| agr CLI | 0.6.1 |
| 批量 | 5 次冷启动，**run 间隔 30s**（非探针周期） |
| 探针周期（v2） | HTTPS 2s；ADB connect/getprop **1s 间隔**，getprop 超时 **3s**（非 30s） |

## 为什么要 `disconnect`？

测试用例**确实每次 delete + create 远端实例**，但 `agr instance mobile connect` 会在**探针客户端本机**留下：

- 后台 WebSocket 隧道进程（`~/.agr/tunnel-<id>.log`）
- `adb devices` 里的 `127.0.0.1:<port>` 条目

`instance delete` **不会**自动清理这些本地状态。批量跑时旧隧道会堆积，旧脚本取 `adb devices` 第一行就会连到已删除实例 → 出现虚假的 ~99s 和超时。

因此 v2 探针在每次 run 前后执行 `agr instance mobile disconnect`（批量开始前 `disconnect --all`）。

## 方法（v2）

1. `agr instance mobile disconnect --all`（preflight）
2. `agr instance create` → `t_api_create` / `t_status_running`
3. `AcquireSandboxInstanceToken` → `t_token`
4. 并行 HTTPS：`:4723/status`、`:8080/healthz`、`:8000/`
5. **一次** `agr instance mobile connect`，用返回的 `AdbAddress` 作为 serial（不用 `devices[0]`）
6. `t_adb_tunnel_ready`：serial 处于 `device` 状态
7. 每 1s `getprop sys.boot_completed`（超时 3s）→ `t_android_boot`
8. cleanup：`disconnect` + `instance delete`
9. `t_e2e_usable = max(t_appium_ready, t_android_boot)`

脚本：`probe/agr-mobile-coldstart-bench.py`；批量：`probe/agr-mobile-coldstart-batch.sh 5`

## 批量结果摘要 v2（n=5，探针修复后）

| 指标 | p50 (ms) | p90 (ms) | 备注 |
|------|----------|----------|------|
| t_api_create / t_status_running | **2007** | 2771 | 创建响应即 RUNNING |
| t_token | **2494** | 3266 | |
| t_appium_ready | **5248** | 6528 | sidecar ~5s |
| t_scrcpy_ready | **4436** | 6723 | |
| t_health_ready | **13571** | 14807 | |
| t_adb_tunnel_ready | **18476** | 19651 | ADB 隧道可用 |
| t_android_boot | **19685** | 21217 | `sys.boot_completed=1` |
| t_e2e_usable | **19685** | 21217 | max(Appium, boot) |

**成功率：** **5/5（100%）**

**Gap（v2）：** Token → e2e p50 **17.0s**；Token → Android boot p50 **17.2s**

汇总 JSON：[`probe/artifacts/coldstart-batch-summary-5runs.json`](../../probe/artifacts/coldstart-batch-summary-5runs.json)

## 各次明细 v2

| run_id | 成功 | t_appium | t_adb_tunnel | t_android_boot | t_e2e |
|--------|------|----------|--------------|----------------|-------|
| 092744Z | ✅ | 4319 | 19914 | 21709 | 21709 |
| 092839Z | ✅ | 5886 | 18476 | 19685 | 19685 |
| 092930Z | ✅ | 6956 | 19257 | 20478 | 20478 |
| 093022Z | ✅ | 4543 | 18227 | 19456 | 19456 |
| 093115Z | ✅ | 5248 | 17203 | 18436 | 18436 |

## v1 vs v2 对比（为何之前是 ~99s）

| | v1（有 bug） | v2（修复后） |
|--|-------------|-------------|
| ADB serial 来源 | `adb devices` 第一行 | `connect` 返回的 `AdbAddress` |
| getprop 超时 | **30s** × 多次失败 | **3s** |
| 本地隧道清理 | 无 | preflight + cleanup `disconnect` |
| t_android_boot p50 | **99427ms**（虚假） | **19685ms** |
| 成功率 | 3/5 | **5/5** |

**结论：** Appium ~5s 与 Android boot ~20s **不矛盾**——sidecar 先就绪，Android 后完成 boot；之前 ~99s 是探针连错隧道 + 30s 超时累积的假象。

## 结论（v2，样本仍偏小）

1. **控制面 ~2s** 返回 `RUNNING`。
2. **Appium/scrcpy ~5s** 可用（sidecar 层）。
3. **Android `boot_completed` ~20s**（ADB 路径，p50 ~19.7s）。
4. **UI 自动化 SLA** 可用 `t_appium_ready`；**原生 ADB SLA** 用 `t_android_boot`。

## 待改进

- [ ] 扩大样本（n≥30）后再报 p99
- [ ] 单独量化 `agr mobile connect` 阻塞等待 adbd 的耗时（当前 tunnel ~18s 含 connect 内部等待）
