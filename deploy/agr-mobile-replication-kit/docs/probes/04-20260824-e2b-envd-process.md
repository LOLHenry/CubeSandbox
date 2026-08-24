# 探测 04 — E2B SDK 能否观测 envd 进程（2026-08-24）

> **序号 04 / 共 04** · 在探测 03 基础上，用更多 E2B SDK 接口判断 mobile 实例内是否存在可观测的 envd 进程。  
> 前序：[`03-20260824-e2b-envd-semantics.md`](03-20260824-e2b-envd-semantics.md)  
> 脚本：[`../../probe/e2b-envd-process-probe.py`](../../probe/e2b-envd-process-probe.py)  
> 产物：[`../../probe/artifacts/04-20260824-e2b-envd-process/`](../../probe/artifacts/04-20260824-e2b-envd-process/)

## 结论（定论）

**E2B SDK 无法判断 mobile 实例内是否存在 envd 进程。**

控制面会返回 `envd_version` 和 `_envd_access_token`，但所有依赖 envd 数据面的 SDK 接口均失败（网关 `310508`）。因此：

- **不能**通过 `commands.run("ps | grep envd")` 查进程（envd RPC 未配置）
- **不能**通过 `files.read("/proc/...")` 读进程信息（同上）
- **不能**通过 `pty.create()` 开 shell（同上）
- **不能**通过 `is_running()` / `:49983/health` 证明 envd 存活（网关拒绝转发）

| 接口 | 能否用于判断 envd 进程 | 实测 |
|------|------------------------|------|
| `Sandbox.create()` | ❌ 仅创建实例 | ✅ 成功 |
| `get_info().envd_version` | ⚠️ 控制面元数据，**非进程探测** | ✅ 返回 `0.2.10` |
| `_envd_access_token` / `envd_api_url` | ⚠️ 鉴权/URL 模板，**非进程探测** | ✅ 存在 |
| `get_host(49983)` | ⚠️ DNS 存在，**后端未配置** | ✅ hostname；HTTP → `310508` |
| `is_running()` | ✅ 设计上探测 envd health | ❌ `310508` |
| `commands.run("ps…envd")` | ✅ 若 envd 可用可列进程 | ❌ `310508` |
| `files.read("/proc/1/cmdline")` | ✅ 若 envd 可用可读文件 | ❌ `310508` |
| `pty.create()` | ✅ 若 envd 可用可开 shell | ❌ `310508` |
| `get_host(4723)/status` | ❌ Appium 对照，与 envd 无关 | ✅ HTTP 200 |

**解读：** `envd_version: 0.2.10` 是平台/E2B 兼容层的**模板元数据**，不代表实例内真有 envd 进程在 `:49983` 监听。mobile 类型把 envd 数据面关掉了，SDK 侧**没有替代接口**能列进程或读 `/proc`。

## 探测实例

| 项 | 值 |
|----|-----|
| Tool | `mobile-arch-probe-1787551777` |
| 实例 1 | `zdlh5jujysw2entxt3ac326w3kyrkqpdtbho33df` |
| 实例 2 | `6mbmas3zkvg7pzdosoqpcneckwmaw37aqlh4wp4e` |
| SDK | `e2b` 2.45.1 |

## 复现

```bash
export E2B_DOMAIN=ap-shanghai.tencentags.com
export E2B_API_KEY=<AGR API Key>
export E2B_VALIDATE_API_KEY=false
python3 deploy/agr-mobile-replication-kit/probe/e2b-envd-process-probe.py
```

## 与探测 02 / 03 的关系

| 视角 | 探测 02（ADB/curl） | 探测 03（SDK 语义） | 探测 04（SDK 进程） |
|------|---------------------|---------------------|---------------------|
| `:49983` 监听 | Android 内无监听 | SDK `commands` 失败 | `is_running`/HTTP health 失败 |
| envd 进程 | `ps` 无 envd | 未测进程 | **SDK 无法测进程** |
| 控制面 `envd_version` | 未测 | 未强调 | **有元数据但不可信为进程证据** |

探测 02 在 Android 侧未发现 envd 进程；探测 04 说明即使用 E2B SDK 也**无法从外部证实或否定**进程存在——唯一可靠结论是 **envd 数据面未暴露，SDK 无 envd 进程观测能力**。
