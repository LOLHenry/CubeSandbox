# 冷启动基准产物（2026-08-24 · ap-shanghai）

探测 06 原始 JSON 与批量汇总。

## 汇总

| 文件 | 说明 |
|------|------|
| [`../coldstart-batch-summary-5runs.json`](../coldstart-batch-summary-5runs.json) | **v2** 5 次批量 p50/p90（探针修复后，5/5 成功） |

## v2 单次 run（探针修复后 · 推荐参考）

| 目录 | 成功 | t_appium | t_android_boot | t_e2e |
|------|------|----------|----------------|-------|
| [`../coldstart-20260824T092744Z`](../coldstart-20260824T092744Z/result.json) | ✅ | 4319 | 21709 | 21709 |
| [`../coldstart-20260824T092839Z`](../coldstart-20260824T092839Z/result.json) | ✅ | 5886 | 19685 | 19685 |
| [`../coldstart-20260824T092930Z`](../coldstart-20260824T092930Z/result.json) | ✅ | 6956 | 20478 | 20478 |
| [`../coldstart-20260824T093022Z`](../coldstart-20260824T093022Z/result.json) | ✅ | 4543 | 19456 | 19456 |
| [`../coldstart-20260824T093115Z`](../coldstart-20260824T093115Z/result.json) | ✅ | 5248 | 18436 | 18436 |
| [`../coldstart-20260824T092651Z`](../coldstart-20260824T092651Z/result.json) | ✅ | 5764 | 19949 | 19949 | 单次验证 |

## v1 单次 run（旧探针 · 仅供参考，~99s 为假象）

| 目录 | 成功 | t_e2e_usable (ms) | 备注 |
|------|------|-------------------|------|
| [`../coldstart-20260824T084209Z`](../coldstart-20260824T084209Z/result.json) | ❌ | — | 脚本 init 失败（已修复） |
| [`../coldstart-20260824T084248Z`](../coldstart-20260824T084248Z/result.json) | ❌ | — | Token 解析 bug（已修复） |
| [`../coldstart-20260824T084311Z`](../coldstart-20260824T084311Z/result.json) | ✅ | 99312 | 旧探针：连错 serial |
| [`../coldstart-20260824T084929Z`](../coldstart-20260824T084929Z/result.json) | ✅ | 99427 | 旧探针批量 |
| [`../coldstart-20260824T085142Z`](../coldstart-20260824T085142Z/result.json) | ✅ | 219511 | 旧探针批量 |
| [`../coldstart-20260824T085554Z`](../coldstart-20260824T085554Z/result.json) | ✅ | 57853 | 旧探针批量 |
| [`../coldstart-20260824T085724Z`](../coldstart-20260824T085724Z/result.json) | ❌ | — | 旧探针 ADB 超时 |
| [`../coldstart-20260824T090300Z`](../coldstart-20260824T090300Z/result.json) | ❌ | — | 旧探针 ADB 超时 |

正文报告：[`docs/probes/06-20260824-mobile-coldstart-bench.md`](../../../docs/probes/06-20260824-mobile-coldstart-bench.md)
