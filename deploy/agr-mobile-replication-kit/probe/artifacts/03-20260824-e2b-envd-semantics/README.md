# 探测 03 产物 — E2B SDK envd 语义验证（2026-08-24）

对应报告：[`../../docs/probes/03-20260824-e2b-envd-semantics.md`](../../docs/probes/03-20260824-e2b-envd-semantics.md)

| 文件 | 说明 |
|------|------|
| `result.json` | 结构化探测结果（API Key 已脱敏） |
| `probe.log` | 完整终端输出 |

## 复现

```bash
export E2B_DOMAIN=ap-shanghai.tencentags.com
export E2B_API_KEY=<从 AGR 控制台或 agr api call CreateAPIKey 获取>
export E2B_VALIDATE_API_KEY=false
python3 probe/e2b-envd-semantics-probe.py
```
