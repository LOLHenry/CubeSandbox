# AGR 官方参考（速查）

> 实测报告按时间顺序见 [`probes/README.md`](probes/README.md)。

## 实测报告时间线

| 序号 | 报告 | 日期 | 位置 |
|------|------|------|------|
| 01 | [mobile-hardware-mock](probes/01-20260723-mobile-hardware-mock.md) | 2026-07-23 | 外部仓库索引 |
| 02 | [mobile-architecture](probes/02-20260824-mobile-architecture.md) | 2026-08-24 | 本仓库 + [`probe/artifacts/02-20260824-ap-shanghai/`](../probe/artifacts/02-20260824-ap-shanghai/README.md) |
| 03 | [e2b-envd-semantics](probes/03-20260824-e2b-envd-semantics.md) | 2026-08-24 | 本仓库 + [`probe/artifacts/03-20260824-e2b-envd-semantics/`](../probe/artifacts/03-20260824-e2b-envd-semantics/README.md) |
| 04 | [e2b-envd-process](probes/04-20260824-e2b-envd-process.md) | 2026-08-24 | 本仓库 + [`probe/artifacts/04-20260824-e2b-envd-process/`](../probe/artifacts/04-20260824-e2b-envd-process/README.md) |
| 05 | [sidecar-oci-pid](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md) | 2026-08-24 | 本仓库（推断 + 源码） |

**结论总索引：** [`FINDINGS.md`](FINDINGS.md) · 端口与架构以探测 02 为准；envd 以 03/04 定论；OCI/PID 以 05 归档。

## 凭据与接入

```bash
export TENCENTCLOUD_SECRET_ID=...      # CAM SecretId
export TENCENTCLOUD_SECRET_KEY=...     # CAM SecretKey
export E2B_API_KEY=...                 # AGS API Key（E2B 兼容）
export REGION=ap-shanghai
export E2B_DOMAIN=ap-shanghai.tencentags.com

agr init --secret-id "$TENCENTCLOUD_SECRET_ID" --secret-key "$TENCENTCLOUD_SECRET_KEY" --non-interactive
agr config set region "$REGION"
agr config set domain tencentags.com
```

> 当前 Cloud Agent VM **未注入**上述凭据；历史报告内值为 `...` 脱敏。请在 Cursor Environment Secrets 重新配置后运行 `probe/agr-probe-mobile.sh`。

## 已实测 Tool / Instance

| 名称 | ToolId | 类型 | 日期 |
|------|--------|------|------|
| mobile-arch-probe | `sdt-osj4kvz6` | mobile | 2026-08-24 |
| mobile-probe | `sdt-n5tzhruw` | mobile | 2026-07-23 |
| android-world-probe | `sdt-pd9yjy00` | android-world | 2026-07-23 |

## CLI 版本（参考）

- `agr` **0.6.1**（2026-06-05 build）
- 控制面：`ags.tencentcloudapi.com`
- 数据面：`*.tencentags.com`

## SDK 示例（官方文档）

```python
from e2b import Sandbox
sandbox = Sandbox.create(template="mobile-v1", timeout=600)
token = sandbox._envd_access_token
# Appium: https://{sandbox.get_host(4723)} + X-Access-Token
# scrcpy: sandbox.get_host(8000), udid emulator-5554
```

## 端口速查（2026-08-24 实测）

| 端口 | 服务 | 暴露方式 |
|------|------|----------|
| 4723 | Appium 3.1.1 | HTTPS + X-Access-Token |
| 8000 | ws-scrcpy Web | HTTPS + access_token |
| 8080 | Health Agent | HTTPS + X-Access-Token |
| 5556 | ADB WebSocket | `agr instance mobile connect` |
| 5555 | adbd | 经 5556 桥接 |
| 8886 | scrcpy-server | 经 8000 proxy-adb |
| 49983 | envd | ❌ mobile 未配置 |

## 完整实测报告

- 探测 01（2026-07-23）：[外部仓库正文](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md) · [本仓库索引](probes/01-20260723-mobile-hardware-mock.md)
- 探测 02（2026-08-24）：[本仓库正文](probes/02-20260824-mobile-architecture.md)
