# 冷启动基准产物（2026-08-24 · ap-shanghai）

探测 06 原始 JSON 与批量汇总。

## 汇总

| 文件 | 说明 |
|------|------|
| [`../coldstart-batch-summary-5runs.json`](../coldstart-batch-summary-5runs.json) | 5 次批量 p50/p90 汇总 |

## 单次 run

| 目录 | 成功 | t_e2e_usable (ms) | 备注 |
|------|------|-------------------|------|
| [`../coldstart-20260824T084209Z`](../coldstart-20260824T084209Z/result.json) | ❌ | — | 脚本 init 失败（已修复） |
| [`../coldstart-20260824T084248Z`](../coldstart-20260824T084248Z/result.json) | ❌ | — | Token 解析 bug（已修复） |
| [`../coldstart-20260824T084311Z`](../coldstart-20260824T084311Z/result.json) | ✅ | 99312 | 首次完整成功 |
| [`../coldstart-20260824T084929Z`](../coldstart-20260824T084929Z/result.json) | ✅ | 99427 | 批量 run 1/5 |
| [`../coldstart-20260824T085142Z`](../coldstart-20260824T085142Z/result.json) | ✅ | 219511 | 批量 run 2/5 |
| [`../coldstart-20260824T085554Z`](../coldstart-20260824T085554Z/result.json) | ✅ | 57853 | 批量 run 3/5 |
| [`../coldstart-20260824T085724Z`](../coldstart-20260824T085724Z/result.json) | ❌ | — | ADB 探活超时 |
| [`../coldstart-20260824T090300Z`](../coldstart-20260824T090300Z/result.json) | ❌ | — | ADB 探活超时 |

正文报告：[`docs/probes/06-20260824-mobile-coldstart-bench.md`](../../../docs/probes/06-20260824-mobile-coldstart-bench.md)
