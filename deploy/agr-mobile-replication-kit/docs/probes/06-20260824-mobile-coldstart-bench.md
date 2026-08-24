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
| 批量 | 5 次冷启动，间隔 30s |
| 轮询 | `instance.get`：创建即 `RUNNING` 未触发轮询；数据面探活 2s |

## 方法

1. `agr instance create` → 记 `t_api_create` / `t_status_running`
2. `AcquireSandboxInstanceToken` → `t_token`
3. 并行 HTTPS：`:4723/status`、`:8080/healthz`、`:8000/`
4. `agr instance mobile connect` + `adb devices` + `sys.boot_completed` → `t_adb_ready`
5. `t_e2e_usable = max(t_appium_ready, t_adb_ready)`

脚本：`probe/agr-mobile-coldstart-bench.py`；批量：`probe/agr-mobile-coldstart-batch.sh 5`

## 批量结果摘要（n=5）

| 指标 | p50 (ms) | p90 (ms) | 备注 |
|------|----------|----------|------|
| t_api_create / t_status_running | **1906** | 2166 | 创建响应即 RUNNING |
| t_token | **2405** | 2650 | |
| t_appium_ready | **5236** | 6010 | 稳定 ~5s |
| t_scrcpy_ready | **4736** | 5109 | |
| t_health_ready | **13505** | 14063 | |
| t_e2e_usable（仅成功 3/5） | **99427** | 195495 | **ADB 路径瓶颈** |

**成功率：** 3/5（60%）— 2 次 `data_plane_timeout`（ADB 探活 300s 超时）

**Gap（成功样本）：** 控制面 RUNNING → Token ~485ms；Token → e2e p50 **96.6s**

汇总 JSON：[`probe/artifacts/coldstart-batch-summary-5runs.json`](../../probe/artifacts/coldstart-batch-summary-5runs.json)

## 各次明细

| run_id | 成功 | t_api_create | t_appium | t_adb | t_e2e |
|--------|------|-------------|----------|-------|-------|
| 084929Z | ✅ | 2312 | 4874 | 99427 | 99427 |
| 085142Z | ✅ | 1880 | 5236 | 219511 | 219511 |
| 085554Z | ✅ | 1946 | 5775 | 57853 | 57853 |
| 085724Z | ❌ | 1906 | 6167 | — | — |
| 090300Z | ❌ | 1575 | 3904 | — | — |

## 结论（⚠️ 初探，样本量小）

1. **控制面极快：** ~2s 返回 `RUNNING`，未见 `STARTING` 轮询窗口。
2. **Appium/scrcpy ~5s 可用：** 与架构报告一致，sidecar 层先就绪。
3. **e2e 瓶颈在 ADB 探针：** 成功样本 58s–220s，且 2/5 超时失败。
4. **探针局限：** 批量跑时本地 `adb devices` 累积多个 `127.0.0.1:port` 隧道，脚本取列表首行可能连到旧实例 → 后续需 `disconnect` + 匹配本次 serial。

## 待改进（下一轮）

- [ ] 每次 run 前后 `agr instance mobile disconnect`
- [ ] ADB 探活使用本次 `connect` 返回的 serial，而非 `devices` 第一行
- [ ] 区分 SLA：`t_appium_ready`（UI 自动化）vs `t_adb_ready`（原生 ADB）
- [ ] 扩大样本（n≥30）后再报 p99
