# AGR Mobile 架构探测报告（2026-08-24 实测）

实例：`qjqwkxvkjvqqqkmguqai4s6rlzfhds7rb2oajex7`  
Tool：`sdt-osj4kvz6` (type=mobile)  
地域：`ap-shanghai`  
原始探测输出目录：`/tmp/agr-arch-probe-phase2/`

## 证据等级图例

| 标记 | 含义 |
|------|------|
| 📘 官方文档 | 腾讯云 AGR 公开文档明确写出 |
| ✅ ADB实测 | 本次 `agr instance mobile adb` 可复现 |
| ✅ HTTPS实测 | 本次数据面 HTTPS + `X-Access-Token` 可复现 |
| ✅ CLI实测 | 本次 `agr` CLI 日志/输出可复现 |
| 📗 历史实测 | 2026-07-23 LOLHenry 报告，与本次一致 |
| ❓ 未证实 | 监听存在但进程归属/拓扑未能从 ADB 命名空间内确认 |
