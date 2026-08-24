# AGR Mobile 探测结论索引

本页汇总**所有已记录结论**及其**证据出处**，按主题索引。探测报告按时间顺序编号，见 [`probes/README.md`](probes/README.md)。

**证据等级**：✅ 实测证实 · ⚠️ 源码/架构推断 · ❌ 实测否定 · 📘 官方文档

---

## 1. 运行时栈与分层

| 结论 | 等级 | 正文 | 原始证据 |
|------|------|------|----------|
| AGR mobile = Cube MicroVM + Linux sidecar + SmartRun/ReDroid Android 14 | ✅ | [探测 02 §虚拟化](probes/02-20260824-mobile-architecture.md) | `probe/artifacts/02-.../phase2/02-dmi.txt`, `20-kernel-cmdline.txt`, `03-getprop-core.txt` |
| 非 Cuttlefish / 非经典 AVD | ✅ | 探测 02 | `03-getprop-core.txt`, `19-android-fingerprint.txt` |
| Appium/ws-scrcpy/health/ADB 桥在 **Linux sidecar 层** | ✅ | 探测 02 §Sidecar | `33-auth-probes.txt`, `08-proc-grep.txt` |
| Android 层：adbd :5555、scrcpy-server :8886 | ✅ | 探测 02 §端口映射 | `04-netstat.txt`, `phase1-live/08_cmd.txt` |

---

## 2. 命名空间（PID / 网络）

| 结论 | 等级 | 正文 | 原始证据 |
|------|------|------|----------|
| Sidecar 与 Android **共享 netns**，**不共享 PID ns** | ✅ | [探测 02 §结构示意（PID 视角）](probes/02-20260824-mobile-architecture.md) | `12-ns-net.txt`, `04-netstat.txt`, `18-pid-namespace.txt` |
| `pid:[4026532547]` 是 PID **命名空间 inode**，不是进程号 | ✅ | 探测 02 §PID 1 与 inode 区别 | `18-pid-namespace.txt` |
| Android 视图下 PID 1 = `init second_stage`，**不是** Appium/node | ✅ | 探测 02 | `phase1-live/05_cmd.txt`, `06_cmd.txt`, `08_cmd.txt` |
| **PID 1 不独占 eth0**；多进程同 netns 各 bind 不同端口 | ✅ | 探测 02 + [探测 05 §网络](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md) | `phase1-live/10_cmd.txt`（eth0）, `04-netstat.txt` |
| Sidecar 端口 netstat PID 显示 `-`（跨 PID ns 不可见属主） | ✅ | 探测 02 | `04-netstat.txt`, `15-inode-pid-map.txt` |
| Sidecar PID ns 的 PID 1 身份 | ⚠️ | [探测 05 §PID 层级](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md) | 推断；`agr instance exec` 失败未实测 |

---

## 3. envd 与 E2B SDK

| 结论 | 等级 | 正文 | 原始证据 |
|------|------|------|----------|
| mobile 类型 **不暴露** envd 数据面 `:49983` | ✅ | [探测 02](probes/02-20260824-mobile-architecture.md)、[探测 03](probes/03-20260824-e2b-envd-semantics.md) | `32-envd-health.txt`；SDK `310508` |
| `commands.run` / `files.write` / `is_running` 均不可用 | ✅ | 探测 03 | `probe/artifacts/03-.../result.json` |
| `get_info().envd_version` 有值但**不能证明** envd 进程存在 | ✅ | [探测 04](probes/04-20260824-e2b-envd-process.md) | `probe/artifacts/04-.../result.json` |
| Android 内无 envd 进程/监听 | ✅ | 探测 02 | `04-netstat.txt`, `08-proc-grep.txt` |
| 同实例 Appium `:4723` 正常（对照） | ✅ | 探测 03、04 | `33-auth-probes.txt`, `04/result.json` |

---

## 4. OCI 打包与 Cube 架构

| 结论 | 等级 | 正文 | 原始证据 |
|------|------|------|----------|
| Sidecar **不是**打进 ReDroid 同一 OCI 镜像 | ✅/⚠️ | [探测 05 §OCI 打包](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md) | PID ns 分离 + Linux 路径 + 无 node 于 Android ps |
| 推测：**多容器 cubebox**（sidecar 镜像 + Android 镜像） | ⚠️ | 探测 05 | `05-mounts.txt`（`/.container_ro_*`）；`CubeMaster/integration/cubebox_helpers_test.go` |
| `tpl create-from-image` 仅生成**单容器**模板 | ✅ | 探测 05 | `CubeMaster/pkg/templatecenter/template_request.go` |
| 鲲鹏复刻 = **单镜像** Android+envd，无 sidecar | ✅ | [`ARCHITECTURE.md`](../ARCHITECTURE.md) §2 | `deploy/sandbox-images/sandbox-android-redroid-envd/Dockerfile` |
| MicroVM 来宾 PID 1 = **cube-agent** | ✅ | 探测 05 | `agent/README.md` |
| ReDroid 在其 PID ns 内须为 PID 1（`exec /init`） | ⚠️ | 探测 05 §ReDroid init | 官方 ENTRYPOINT；[redroid-doc#758](https://github.com/remote-android/redroid-doc/issues/758)；本仓库 `envd-starter` |

---

## 5. 文档地图

| 文件 | 内容 |
|------|------|
| [`probes/README.md`](probes/README.md) | 探测报告时间线与阅读顺序 |
| [`probes/02-...`](probes/02-20260824-mobile-architecture.md) | **主架构报告**：分层、端口、PID/netns、数据通路 |
| [`probes/03-...`](probes/03-20260824-e2b-envd-semantics.md) | E2B SDK envd 语义不可用 |
| [`probes/04-...`](probes/04-20260824-e2b-envd-process.md) | E2B SDK 无法观测 envd 进程 |
| [`probes/05-...`](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md) | Sidecar OCI 打包推测、PID 层级、网络、复刻实施要点 |
| [`ARCHITECTURE.md`](../ARCHITECTURE.md) | AGR 官方 vs 鲲鹏复刻对照 |
| [`AGR_REFERENCE.md`](AGR_REFERENCE.md) | 操作速查与端口表 |
| [`OPTIONAL_COMPONENTS.md`](OPTIONAL_COMPONENTS.md) | 复刻侧可选 Appium/scrcpy（单镜像路线） |

---

## 6. 未证实 / 待补探测

| 项 | 状态 |
|----|------|
| Sidecar 容器 PID 1 具体二进制 | ❓ `agr instance exec` 失败 |
| 腾讯 sidecar OCI 镜像名 / Dockerfile | ❓ 未公开 |
| Sidecar 启动机制（systemd/s6/自定义） | ❓ 未公开 |
| `:32001` 端口用途 | ❓ 仅见监听 |
| AGR mobile 多容器 cubebox 完整 spec JSON | ❓ 平台内部；用户不可配 → [`OFFICIAL_MULTI_CONTAINER.md`](../OFFICIAL_MULTI_CONTAINER.md) |
