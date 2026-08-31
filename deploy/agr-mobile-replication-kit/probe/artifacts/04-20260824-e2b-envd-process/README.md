# 探测 04 产物 — E2B SDK envd 进程可观测性（2026-08-24）

报告：[`../../docs/probes/04-20260824-e2b-envd-process.md`](../../docs/probes/04-20260824-e2b-envd-process.md)

| 文件 | 说明 |
|------|------|
| `result.json` | 结构化探测结果 |
| `probe.log` | 终端完整输出 |

```bash
export E2B_DOMAIN=ap-shanghai.tencentags.com
export E2B_API_KEY=<从 agr api call CreateAPIKey 获取>
export E2B_VALIDATE_API_KEY=false
python3 probe/e2b-envd-process-probe.py
```
