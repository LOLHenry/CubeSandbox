# 探测 03 — E2B SDK envd 语义验证（2026-08-24）

> **序号 03 / 共 03** · 验证 mobile 类型是否在任何层面提供 envd 语义。  
> 前序：[`02-20260824-mobile-architecture.md`](02-20260824-mobile-architecture.md)  
> 原始输出：[`../../probe/artifacts/03-20260824-e2b-envd-semantics/`](../../probe/artifacts/03-20260824-e2b-envd-semantics/)

## 结论（定论）

**AGR `mobile` 类型不提供 envd 语义。** E2B SDK 的 `commands.run()`、`files.write()`、`is_running()` 均直接失败，错误为平台网关 `310508`：

> The requested sandbox endpoint is not configured. Check that the sandbox port is exposed

这不是「Redroid 内看不到」的问题，而是 **E2B SDK 走 `:49983` envd 通道时，平台未配置该端点**。同一实例上 Appium `:4723` 正常工作。

探测 04 进一步覆盖 `get_info().envd_version`、`is_running()`、`pty.create()`、`commands.run("ps…envd")` 等接口，结论见 [`04-20260824-e2b-envd-process.md`](04-20260824-e2b-envd-process.md)：**SDK 无法观测 envd 进程**；控制面 `envd_version` 仅为元数据。

| SDK 调用 | 结果 | 错误 |
|----------|------|------|
| `Sandbox.create(template=...)` | ✅ 成功 | — |
| `_envd_access_token` | ✅ 存在 | Token 用于数据面鉴权，**不意味着 envd 可用** |
| `get_host(49983)` | ✅ 返回 hostname | 仅 DNS 模式存在，后端未配置 |
| `commands.run("echo hi")` | ❌ 失败 | `310508 endpoint not configured` |
| `files.write(...)` | ❌ 失败 | 同上 |
| `is_running()` | ❌ 失败 | 同上 |
| `get_host(4723)` + `/status` | ✅ HTTP 200 | Appium ready（对照实验） |

## 探测方法

```python
from e2b import Sandbox

os.environ["E2B_DOMAIN"] = "ap-shanghai.tencentags.com"
os.environ["E2B_API_KEY"] = "<AGS API Key>"  # agr api call CreateAPIKey

sandbox = Sandbox.create(template="mobile-arch-probe-1787551777", timeout=600)
sandbox.commands.run("echo hi")   # → SandboxException 310508
sandbox.files.write("/tmp/x", "hi")  # → SandboxException 310508
```

Tool：`mobile-arch-probe-1787551777` (`sdt-osj4kvz6`)  
测试实例：`iumkhf6jlju2f4vpb46yjhfkakfb2l3gkovsrhfk`

## 与探测 02 的关系

| 探测 02（HTTPS/curl） | 探测 03（E2B SDK） |
|----------------------|-------------------|
| `curl :49983/health` → 310508 | `commands.run` → 同错误 |
| 推断 mobile 无 envd | **SDK 层证实：无隐藏通道** |

## E2B「兼容」在 mobile 上的实际含义

| E2B SDK 能力 | mobile 是否可用 |
|--------------|----------------|
| `Sandbox.create()` / `kill()` | ✅ 控制面兼容 |
| `_envd_access_token` / `get_host(port)` | ✅ 有（Token + 端口 hostname） |
| `commands.*` / `files.*` / envd health | ❌ **不可用**（envd 未暴露） |
| Appium（`get_host(4723)`） | ✅ 可用（官方文档路径） |
| scrcpy（`get_host(8000)`） | ✅ 可用（官方文档路径） |

`_envd_access_token` 命名来自 E2B SDK 历史，在 mobile 上实际作用是 **数据面 `X-Access-Token` 鉴权**，不是 envd HTTP/RPC 可用的证据。

## 对鲲鹏复刻包的含义

本仓库复刻包设计 **envd + ADB 双通道** 是 CubeSandbox 侧的能力选择，**不是** AGR mobile 官方的一比一复制。AGR mobile 官方控制面是 **Appium + ADB + scrcpy**，不含 envd command/file API。
