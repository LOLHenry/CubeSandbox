# AGR 多容器与 Sidecar：官方支持边界

> 回答：「mobile 多容器模板是否走平台内部流水线、具体怎么弄、是否官方支持」  
> 索引：[`FINDINGS.md`](FINDINGS.md) · 架构推断：[`probes/05-20260824-sidecar-oci-and-pid-hierarchy.md`](probes/05-20260824-sidecar-oci-and-pid-hierarchy.md)

## 一句话

| 场景 | 是否官方支持用户「配多容器」 | 怎么做 |
|------|------------------------------|--------|
| **AGR 云端 `mobile` 类型** | ❌ **不支持**用户自定义多容器 / sidecar 镜像 | `agr tool create -t mobile`，用平台预置环境 |
| **AGR 云端 `aio` 类型** | ✅ 支持，但是**单镜像多能力**，不是 mobile sidecar+Android | 控制台建 AIO 工具 + 自定义合并镜像 |
| **AGR 云端 `custom` 类型** | ✅ 支持**单容器**自定义镜像 | `agr tool create -t custom --request @tool.json` |
| **自托管 CubeSandbox** | ✅ 运行时支持多容器 cubebox | `CreateCubeSandboxReq.containers[]` + `tpl commit`（非 `create-from-image`） |

**mobile 内部的 Linux sidecar + Android 双容器编排，属于平台实现细节，未向租户开放配置接口。**

---

## 1. AGR 官方：`mobile` 能做什么、不能做什么

### 官方文档怎么说

- [工具类型说明](https://cloud.tencent.com/document/product/1814/132209)：`mobile` = **预置** Mobile 运行环境 + ADB，开箱即用。
- [CreateSandboxTool API](https://cloud.tencent.com/document/product/1814/124812)：`ToolType` 枚举含 `mobile`、`custom`、`aio` 等；**`mobile` 无 `CustomConfiguration` 镜像字段**。
- 创建示例仅为：`ToolName` + `ToolType: mobile` + `NetworkConfiguration`，无 `containers[]`、无 sidecar 镜像。

```bash
# 用户侧唯一标准路径
agr tool create -n my-mobile -t mobile --network PUBLIC
agr instance create --tool-id <ToolId>
agr instance mobile connect <InstanceId>
```

### 用户不能做的（官方未提供）

- 指定 sidecar OCI 镜像 / Android OCI 镜像
- 配置 `containers[0]` / `containers[1]` 多容器 spec
- 用 `tpl create-from-image` 类接口替换 mobile 内部模板（AGR 控制面无此暴露）
- 从 `tool.get` 读到镜像或多容器定义（实测仅 `ToolType: mobile`）

### 平台内部很可能在做什么（⚠️ 推断，非官方文档）

依据探测 02：`/.container_ro_*` 挂载、sidecar/Android PID ns 分离、Appium Linux 路径。

→ 腾讯云在 **Cube/cubebox 运行时** 内用多容器编排 sidecar + SmartRun/ReDroid，属于**托管实现**，不是租户可编辑的 Tool 配置。

---

## 2. AGR 官方：与「多容器」相关的**已支持**类型

### `aio`（All-In-One）

- [产品动态 2026-04-09](https://cloud.tencent.com/document/product/1814/123809)：新增 **AIO 类型，All-In-One 多容器环境**（4C8G）。
- [AIO 沙箱操作文档](https://cloud.tencent.com/document/product/1814/130978)：强调 **单个合并镜像** 内提供代码执行、浏览器、VSCode、WebShell、envd 等。

**注意：** AIO 的「多容器」在文档语境里更接近 **单实例多能力 / 平台侧编排**，不是 mobile 那种「Linux sidecar + Android」用户可配双镜像。AIO 需 **自定义合并镜像** + 控制台创建 AIO 工具。

### `custom`（自定义单容器）

- [创建沙箱工具 CLI](https://cloud.tencent.com/document/product/1814/132210)：一个 `CustomConfiguration.Image`、一套 `Command`、`Ports`。
- **一个 Tool = 一个容器镜像**，没有公开的 `containers[]` 数组给租户填。

若要把 Appium + ReDroid 塞进 **一个** 镜像，可走 `custom`，但那是**单容器融合镜像**，不是 AGR mobile 官方的 sidecar 分层。

### 存储挂载「一对多」

- [产品动态 2026-03-25](https://cloud.tencent.com/document/product/1814/123809)：同一存储可挂到**多个容器路径** → 证明平台实例层有多容器能力，但 **mobile 工具创建 API 不暴露容器列表**。

---

## 3. 自托管 CubeSandbox：多容器**可以**怎么弄

开源 Cube 与 AGR 同源运行时；**多容器在 API 层支持**，但 **`tpl create-from-image` 只生成单容器**。

### 步骤（路线 A：贴近 AGR sidecar + Android）

**1. 构建两个 OCI 镜像并 push**

```text
your-registry/mobile-sidecar:latest    # Linux: Appium + ws-scrcpy + health + ADB桥
your-registry/mobile-android:latest    # ReDroid/SmartRun, ENTRYPOINT /init
```

**2. 编写 `create-mobile-cubebox.json`（示意）**

```json
{
  "requestID": "create-mobile-multi-001",
  "instance_type": "cubebox",
  "containers": [
    {
      "name": "cubebox-runtime-sidecar",
      "image": { "image": "your-registry/mobile-sidecar:latest" },
      "command": ["/usr/local/bin/sidecar-entrypoint.sh"],
      "resources": { "cpu": "1000m", "mem": "2Gi" }
    },
    {
      "name": "cubebox-runtime-android",
      "image": { "image": "your-registry/mobile-android:latest" },
      "command": ["/init"],
      "args": ["androidboot.hardware=redroid", "androidboot.redroid_width=720"],
      "resources": { "cpu": "4000m", "mem": "6Gi" }
    }
  ],
  "volumes": [ "... empty_dir rootfs writable ..." ],
  "annotations": { "com.exposed_ports": "4723,8000,8080,5556,5555" }
}
```

字段以集群实际 `CreateCubeSandboxReq` / `RunCubeSandboxRequest` 为准；参考：

- `CubeMaster/integration/cubebox_helpers_test.go`（双容器 busybox 示例）
- `CubeMaster/api/services/cubebox/v1/cubebox.proto` `repeated ContainerConfig containers`

**3. 创建沙箱**

```bash
# 经 CubeMaster HTTP API 或 cubemastercli bench multirun（内部测试命令）
cubemastercli bench multirun create-mobile-cubebox.json
```

**4. 验证端口与 ADB 后固化为模板**

```bash
cubemastercli tpl commit --sandbox-id <id> -f create-mobile-cubebox.json
cubemastercli tpl info <template-id> --include-request
```

**5. 不要指望**

```bash
cubemastercli tpl create-from-image --image ...   # 永远只生成 cubebox-name-0 单容器
```

源码：`CubeMaster/pkg/templatecenter/template_request.go` L107–125。

### 步骤（路线 B：单镜像，本仓库 v1）

见 [`OPTIONAL_COMPONENTS.md`](OPTIONAL_COMPONENTS.md) + `scripts/05-create-template.sh`：`create-from-image` + `sandbox-android-redroid-envd`，**无 sidecar 层**。

---

## 4. 对照表

| 能力 | AGR `mobile` | AGR `custom` | AGR `aio` | 自托管 CubeSandbox |
|------|--------------|--------------|-----------|-------------------|
| 用户指定镜像 | ❌ | ✅ 1 个 | ✅ 合并镜像 | ✅ 每容器 1 个 |
| 用户配多容器 | ❌ | ❌ | ⚠️ 平台定义 | ✅ `containers[]` |
| Appium/scrcpy 预置 | ✅ | ❌ 自建 | ❌ | 需自建 sidecar 镜像 |
| envd `:49983` | ❌ mobile 未暴露 | 可 custom 探活 | ✅ AIO 文档有 | ✅ 鲲鹏复刻包 |
| `create-from-image` | N/A（云端无此 CLI） | N/A | N/A | ✅ 仅单容器 |

---

## 5. 建议

| 你的目标 | 建议 |
|----------|------|
| 用腾讯云 **官方 mobile**（Appium/ADB/scrcpy） | `agr tool create -t mobile`，**不要**尝试复刻内部多容器流水线 |
| 在 **AGR 上自定义** Android 环境 | `custom` 单镜像，或联系腾讯工单；**无公开 multi-container mobile API** |
| 在 **自建 Cube** 复刻 AGR 分层 | 路线 A：双镜像 + `containers[]` + `tpl commit` |
| 快速鲲鹏验证 envd+ADB | 路线 B：现有 `agr-mobile-replication-kit` 单镜像 |

若要腾讯官方支持「租户自定义 mobile 多容器模板」，属于**产品能力需求**，当前公开 API/文档**未提供**。
