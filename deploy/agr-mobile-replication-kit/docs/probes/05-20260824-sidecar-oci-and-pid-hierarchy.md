# 探测 05 — Sidecar OCI 打包、PID 层级与网络（2026-08-24）

> **序号 05 / 共 05** · 归档对话中形成的架构推断与补充结论（部分为 Cube 源码推断，非 AGR 官方公开文档）。  
> 前序：[`02-20260824-mobile-architecture.md`](02-20260824-mobile-architecture.md)  
> 索引：[`../FINDINGS.md`](../FINDINGS.md) · [`README.md`](README.md)

## 本文档回答的问题

1. ReDroid / Android 的 PID 1 是谁？是否等于 sidecar？
2. PID 1 是否「接管 eth0」？sidecar 如何用同一网卡？
3. 从 Cube 架构看，各层 PID 1 分别是谁？
4. 腾讯 Linux sidecar 在 OCI 打包时怎么做？
5. 鲲鹏侧若要复刻 AGR 形态，具体怎么弄？

---

## 1. Android 视角：PID 1 = `init`，不是 sidecar

| 观测 | 证据文件 |
|------|----------|
| PID 1 cmdline = `init second_stage` + `androidboot.redroid_*` | `probe/artifacts/02-.../phase1-live/05_cmd.txt` |
| `/proc/1/exe` → `/system/bin/init` | `phase1-live/06_cmd.txt` |
| Android `ps` 无 `node`/`appium` | `phase2-detailed/08-proc-grep.txt` |
| Appium 栈路径 `/usr/lib/node_modules/appium/` | `phase2-detailed/33-auth-probes.txt` |

**结论（✅ 实测）：** 在 Android PID 命名空间 `pid:[4026532547]` 内，**PID 1 = ReDroid `init`**，不是 Appium 或名为 `redroid` 的进程。

---

## 2. 网络：PID 1 不独占 eth0

网络接口归 **网络命名空间**，不归某个 PID。

| 观测 | 含义 | 证据 |
|------|------|------|
| `init`、adbd、scrcpy 共享 `net:[4026531840]` | 同 netns | `phase2-detailed/12-ns-net.txt` |
| eth0 = `169.254.68.6/30` | VM 内链路本地地址 | `phase1-live/10_cmd.txt` |
| `:4723/:8000` 与 `:5555/:8886` 同 netstat 可见 | sidecar 与 Android 同 netns | `phase2-detailed/04-netstat.txt` |
| sidecar 端口 PID 列 `-` | 属主在另一 PID ns | `04-netstat.txt` |

**结论（✅ 实测）：** sidecar 与 Android **共享 eth0（netns）**，各自 `bind` 不同端口；`init` 通过 `netd` 等管路由，**不阻止** sidecar 监听 `:4723` 等。

数据通路见探测 02 §通路 B/C（Appium → ADB → Android；ws-scrcpy :8000 → scrcpy-server :8886）。

---

## 3. PID 层级（Cube 架构推测）

```
宿主机 (containerd / Cubelet)
  └── MicroVM
        └── cube-agent                    ← VM 内全局 PID 1（✅ 源码）
              └── cubebox 沙箱
                    ├── [容器 0] Linux sidecar   ← sidecar PID ns 的 PID 1（⚠️ 推断）
                    │     Appium :4723, ws-scrcpy :8000, ...
                    └── [容器 1] Android         ← Android PID ns 的 PID 1 = init（✅ 实测）
                          adbd :5555, scrcpy-server :8886
```

| 层级 | PID 1（推测/证实） | 依据 | 置信度 |
|------|-------------------|------|--------|
| MicroVM 来宾 | `cube-agent` (`/sbin/init`) | `agent/README.md` L3、L28–32 | ✅ 高 |
| Sidecar 容器 | Linux 容器 init（tini/entrypoint） | 多容器模式 + PID ns 分离 | ⚠️ 中 |
| Android 容器 | `init second_stage` | ADB 实测 | ✅ 高 |

**不等于：**「容器 PID 1 = Linux sidecar 里的 node 进程」。Sidecar **服务**在独立 PID ns；该 ns 的 PID 1 应是**容器入口进程**（监督脚本/tini），不是 Appium 子进程。

### Cube 多容器机制（源码）

- 第一个容器 `index==0` 标记为 `IsPod`（infra）：`Cubelet/services/cubebox/cube_container_create.go` L467–468
- 集成测试命名：`cubebox-runtime-sidecar` + `cubebox-runtime-frame`：`CubeMaster/integration/cubebox_helpers_test.go` L43–72
- 容器间目录传播：`/.container_ro_*` / `/.container_rw_*`：`Cubelet/pkg/constants/const.go`；AGR 实测 `phase2-detailed/05-mounts.txt` L21–22

---

## 4. 腾讯 Linux sidecar 的 OCI 打包（推断）

### 4.1 不是单镜像融合

若 Appium 与 ReDroid 打在同一 OCI 镜像，通常应能在同一 PID ns 或 Android `ps` 中看到 `node`。实测相反 → **sidecar 为独立 Linux OCI 镜像**。

### 4.2 推测打包模型

```
镜像 A：linux-mobile-sidecar（独立 build & push）
  FROM node:20-bookworm-slim
  RUN npm i -g appium@3.1.1 && appium driver install uiautomator2
  COPY ws-scrcpy, health-agent, adb-ws-bridge, sidecar-entrypoint.sh
  EXPOSE 4723 8000 8080 5556
  ENTRYPOINT ["tini", "--", "/usr/local/bin/sidecar-entrypoint.sh"]

镜像 B：smartrun-redroid-android14（独立 build & push）
  ENTRYPOINT ["/init", "androidboot.hardware=redroid", ...]

运行时：一个 cubebox 请求里 containers[0]=sidecar, containers[1]=android
  共享 network namespace，分离 PID namespace
```

### 4.3 与开源 Cube 工具链的差异

| 能力 | 状态 | 出处 |
|------|------|------|
| `RunCubeSandboxRequest.containers[]` 支持多容器 | ✅ API 支持 | `cubebox.proto` L533–539 |
| `tpl create-from-image` | 仅 **单容器** `cubebox-name-0` | `template_request.go` L107–125 |
| AGR mobile 多容器模板 | ❓ 平台内部流水线，仓库无公开 spec | `tool.get` 仅 `ToolType: mobile` |

**结论（⚠️ 推断）：** 腾讯侧 likely 用**内部多容器模板**编排 sidecar + Android；**不是**用户侧 `create-from-image` 单镜像流程。

---

## 5. ReDroid 与 PID 1（补充）

| 点 | 说明 |
|----|------|
| 官方未明文写「init 必须 PID 1」 | ReDroid 文档 ENTRYPOINT 为 `["/init", ...]` |
| 实际须在其 PID ns 内为 1 | 社区 [redroid-doc#758](https://github.com/remote-android/redroid-doc/issues/758)；须 `exec /init` 而非 fork |
| 鲲鹏复刻 | `envd-starter` 作容器 PID 1 → 起 envd → **`exec /init`** 交接 | `deploy/sandbox-images/sandbox-android-redroid-envd/envd-starter/main.go` |

---

## 6. 鲲鹏复刻：两种路线

### 路线 A — 贴近 AGR（多容器 cubebox）

1. **构建 sidecar 镜像**（Linux）：Node + Appium + ws-scrcpy + health + ADB 桥 + `sidecar-entrypoint.sh`
2. **构建 Android 镜像**：现有 `sandbox-android-redroid` 或 SmartRun 底座
3. **编写多容器 `CreateCubeSandboxReq` JSON**（两个 `containers`，`exposed_ports` 含 4723/8000/8080/5556/5555）
4. **创建沙箱** → 验证后 **`tpl commit`** 固化为模板（`cubemastercli tpl commit --sandbox-id ... -f create.json`）
5. **不要用** `tpl create-from-image` 期望一次生成双容器模板

sidecar entrypoint 要点：并行拉起服务；`wait-for-adb 127.0.0.1:5555` 后再启 Appium。

### 路线 B — 简化复刻（单镜像，本仓库 v1）

见 [`OPTIONAL_COMPONENTS.md`](../OPTIONAL_COMPONENTS.md)：在 ReDroid 镜像内叠 Node+Appium，**不是** AGR 官方 sidecar 形态，但可用 `create-from-image` 单容器流程。

对照表见 [`ARCHITECTURE.md`](../../ARCHITECTURE.md) §2。

---

## 7. 置信度汇总

| 结论 | 等级 |
|------|------|
| Android PID 1 = init；sidecar 在另一 PID ns | ✅ 实测 |
| 共享 netns；PID 1 不独占 eth0 | ✅ 实测 |
| VM PID 1 = cube-agent | ✅ 源码 |
| 多容器 cubebox（sidecar + Android） | ⚠️ 推断（挂载标记 + Cube 集成测试） |
| Sidecar 独立 Linux OCI 镜像 | ⚠️ 推断（进程/路径分离） |
| 腾讯 sidecar Dockerfile / 镜像名 | ❓ 未公开 |
