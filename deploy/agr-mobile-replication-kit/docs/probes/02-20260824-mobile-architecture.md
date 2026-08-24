# 探测 02 — AGR Mobile 架构分层与数据面（2026-08-24）

> **序号 02 / 共 02** · 本仓库正文报告。  
> 前序报告：[`01-20260723-mobile-hardware-mock.md`](01-20260723-mobile-hardware-mock.md)（外部仓库，底座与硬件面）  
> 索引：[`README.md`](README.md)  
> 原始探测输出：[`../../probe/artifacts/02-20260824-ap-shanghai/`](../../probe/artifacts/02-20260824-ap-shanghai/README.md)

## 探测概要

| 项 | 值 |
|----|-----|
| 日期 | 2026-08-24 |
| 地域 | `ap-shanghai` |
| 数据面域名 | `ap-shanghai.tencentags.com` |
| Tool ID | `sdt-osj4kvz6` |
| Tool 名称 | `mobile-arch-probe-1787551777` |
| Tool 类型 | `mobile` |
| Instance ID | `qjqwkxvkjvqqqkmguqai4s6rlzfhds7rb2oajex7` |
| 规格 | CPU `4600m` / Memory `8768Mi` / Network `PUBLIC` |
| agr CLI | `0.6.1` |

## 证据等级图例

| 标记 | 含义 |
|------|------|
| 📘 官方文档 | 腾讯云 AGR 公开文档明确写出 |
| ✅ ADB实测 | `agr instance mobile adb` 可复现 |
| ✅ HTTPS实测 | 数据面 HTTPS + `X-Access-Token` 可复现 |
| ✅ CLI实测 | `agr` CLI 日志/输出可复现 |
| 📗 前序实测 | 探测 01 — [01-20260723-mobile-hardware-mock.md](01-20260723-mobile-hardware-mock.md) |
| ❓ 未证实 | 有间接证据，进程级细节未能从 ADB 命名空间内确认 |
| ❌ 实测否定 | 本次探测确认不存在或未配置 |

---

## 总体架构（文本版）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 客户端                                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  • agr CLI          → mobile connect / mobile adb                       │
│    依据：📘 官方文档 + ✅ CLI 隧道日志 (meta/tunnel-adb-wss.log)           │
│  • E2B SDK / Appium → HTTPS 访问数据面端口                                 │
│    依据：📘 手机操作文档 + ✅ HTTPS /status 实测 (phase2/33-auth-probes)    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ CAM SecretId/Key
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 控制面（腾讯云 AGR）                                                      │
├─────────────────────────────────────────────────────────────────────────┤
│  端点：ags.tencentcloudapi.com                                           │
│  能力：创建 Tool(mobile) / Instance，下发 Access Token                    │
│  依据：✅ phase2/20-instance-get.json, 21-tool-get.json                  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ 创建实例后获得 X-Access-Token
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 数据面网关（OpenResty / Cube Proxy）                                      │
├─────────────────────────────────────────────────────────────────────────┤
│  地址：{port}-{instanceId}.ap-shanghai.tencentags.com                    │
│  鉴权：X-Access-Token（无 Token → 401 AUTHENTICATION_FAILED）            │
│  依据：✅ phase2/30-external-https.txt, 33-auth-probes.txt                │
└───────┬─────────────┬─────────────┬─────────────┬───────────────────────┘
        │             │             │             │
   :4723│        :8000│        :8080│   wss :5556 │
        │             │             │   /adb/ws   │
        ▼             ▼             ▼             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Cube Hypervisor MicroVM（实例内）                                         │
│ 依据：✅ phase2/02-dmi.txt, 01-uname.txt, 20-kernel-cmdline.txt           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─ Linux Sidecar 层（与 Android 共享网络，ADB 内看不到其进程）──────────┐  │
│  │                                                                     │  │
│  │  :4723  Appium 3.1.1 (Node.js)                                      │  │
│  │         依据：✅ phase2/33-auth-probes.txt → v3.1.1 ready            │  │
│  │               栈路径 /usr/lib/node_modules/appium/                   │  │
│  │                                                                     │  │
│  │  :8000  ws-scrcpy Web UI (Express)                                  │  │
│  │         依据：✅ phase2/36-scrcpy-html.txt title=WS scrcpy           │  │
│  │               📘 官方 proxy-adb → tcp:8886                           │  │
│  │                                                                     │  │
│  │  :8080  Health Agent (/healthz, /livez)                             │  │
│  │         依据：✅ phase2/34-8080-livez.txt → {"alive":true}           │  │
│  │                                                                     │  │
│  │  :5556  ADB WebSocket 桥                                            │  │
│  │         依据：✅ meta/tunnel-adb-wss.log                             │  │
│  │                                                                     │  │
│  │  注：上述端口在 ADB netstat 可见，但 Android /proc 中无对应 PID        │  │
│  │      依据：✅ phase2/04-netstat.txt + 15-inode-pid-map.txt           │  │
│  └──────────────────────────┬──────────────────────────────────────────┘  │
│                             │ ADB / HTTP 代理                             │
│                             ▼                                             │
│  ┌─ Android 层（SmartRun / ReDroid 14, x86_64）───────────────────────┐  │
│  │  容器 rootfs：overlay2 / cubebox                                     │  │
│  │  依据：✅ phase2/05-mounts.txt                                        │  │
│  │                                                                     │  │
│  │  :5555  adbd                    PID=138                             │  │
│  │         依据：✅ phase1-live/15_cmd.txt, phase2/04-netstat.txt         │  │
│  │                                                                     │  │
│  │  :8886  scrcpy-server (app_process)  PID=3379                       │  │
│  │         依据：✅ phase1-live/08_cmd.txt, phase2/08-proc-grep.txt      │  │
│  │                                                                     │  │
│  │  APK    io.appium.uiautomator2.server / io.appium.settings          │  │
│  │         依据：✅ phase2/09-packages.txt                               │  │
│  │                                                                     │  │
│  │  系统   Android 14 + GMS，外观伪装 OnePlus PJZ110                    │  │
│  │         依据：✅ phase2/03-getprop-core.txt, 19-android-fingerprint  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ❌ :49983 envd — mobile 类型未暴露                                       │
│     依据：✅ phase2/32-envd-health.txt → 310508 not configured           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 三条主要数据通路

### 通路 A：ADB 命令行

```
用户 → agr instance mobile connect
     → 本地 adb connect 127.0.0.1:{local_port}
     → 网关 wss://5556-{instanceId}.ap-shanghai.tencentags.com/adb/ws
     → 实例内 ADB Bridge (:5556)
     → Android adbd (:5555)
```

依据：✅ `meta/tunnel-adb-wss.log`、`phase2/00-connect.txt`、`phase2/00-adb-devices.txt`

### 通路 B：Appium 自动化

```
用户/Appium Client
     → HTTPS :4723-{instanceId}.ap-shanghai.tencentags.com/status
     → 网关（X-Access-Token 鉴权）
     → Sidecar Appium (:4723)
     → ADB → UiAutomator2 APK → Android 系统
```

依据：📘 [手机操作文档](https://cloud.tencent.com/document/product/1814/127484) + ✅ `phase2/33-auth-probes.txt`

### 通路 C：浏览器投屏

```
浏览器
     → HTTPS :8000-{instanceId}.ap-shanghai.tencentags.com
     → 网关（access_token 鉴权）
     → Sidecar ws-scrcpy (:8000)
     → proxy-adb → tcp:8886
     → Android scrcpy-server (:8886)
```

依据：📘 官方 `scrcpy_url` 示例 + ✅ `phase2/36-scrcpy-html.txt`

---

## 端口与服务映射

| 端口 | 服务 | 进程归属 | 依据文件 |
|------|------|----------|----------|
| **5555** | Android `adbd` | ✅ Android PID 138 | `phase2/04-netstat.txt`, `phase1-live/15_cmd.txt` |
| **8886** | scrcpy-server | ✅ Android PID 3379 | `phase1-live/08_cmd.txt` |
| **4723** | Appium 3.1.1 | ❓ Linux sidecar | `phase2/33-auth-probes.txt` |
| **8000** | ws-scrcpy Web | ❓ Linux sidecar | `phase2/36-scrcpy-html.txt` |
| **8080** | Health Agent | ❓ Linux sidecar | `phase2/34-8080-livez.txt` |
| **5556** | ADB WebSocket 桥 | ❓ Linux sidecar | `meta/tunnel-adb-wss.log` |
| **49983** | envd | ❌ mobile 未配置 | `phase2/32-envd-health.txt` |
| **32001** | 未知 | ❓ 仅见监听 | `phase2/04-netstat.txt` |

---

## 虚拟化与 Android 指纹

| 检查项 | 结果 | 文件 |
|--------|------|------|
| DMI Vendor | `Cube Hypervisor` | `phase2/02-dmi.txt` |
| DMI Product | `cube-hypervisor` | `phase2/02-dmi.txt` |
| Guest Kernel | `6.6.69-cube.bm.guest... x86_64` | `phase2/01-uname.txt` |
| Kernel cmdline | `cubevm`, `video=vfb:enable,720x1280...` | `phase2/20-kernel-cmdline.txt` |
| `ro.hardware.gralloc` | `redroid` | `phase2/03-getprop-core.txt` |
| Build | `smartrun_android_x86_64-userdebug 14` | `phase2/03-getprop-core.txt` |
| 外观 model | `PJZ110` (OnePlus 伪装) | `phase2/19-android-fingerprint.txt` |
| 分辨率 | 720×1280 @ 60fps | `phase2/21-display-props.txt` |
| 容器 rootfs | `overlay2` + `cubebox-*` | `phase2/05-mounts.txt` |

与探测 01 §3.1 结论一致：**Cube Hypervisor MicroVM + SmartRun/ReDroid Android 14 x86_64**，非 Cuttlefish、非经典 AVD。

---

## Sidecar 与 Android 命名空间关系

| 观察 | 依据 |
|------|------|
| 4723/8000/8080/5556 在 ADB shell 内 `netstat` 可见 | `phase2/04-netstat.txt` |
| 上述端口在 Android `/proc/*/fd` 中找不到 socket inode 属主 | `phase2/15-inode-pid-map.txt`, `17-inode-fd-grep.txt` |
| Appium 错误栈含 Linux 路径 `/usr/lib/node_modules/appium/` | `phase2/33-auth-probes.txt` |
| Android `ps` 中无 `node`/`appium` 进程 | `phase2/08-proc-grep.txt`, `16-ps-su-all.txt` |
| init/adbd/scrcpy 共享同一 net ns | `phase2/12-ns-net.txt` |
| `agr instance exec` 对 mobile 实例失败 | `phase2/50-instance-exec-linux.txt` |

**结论：** Appium、ws-scrcpy Web、Health、ADB Bridge 运行在 Cube 容器内的 **Linux sidecar 层**（与 Android 共享 netns，但 ADB 所在的 Android PID namespace 看不到这些进程）。

---

## 结构示意（PID 视角）

> 实例：`qjqwkxvkjvqqqkmguqai4s6rlzfhds7rb2oajex7`（2026-08-24 单次快照）。**PID 随重启变化**，但命名空间分层关系稳定。

### PID 1 与 `pid:[4026532547]` 的区别

| 符号 | 含义 | 类比 |
|------|------|------|
| **PID 1** | 进程在**自己 PID 命名空间内的编号** | 班级里的「1 号学生」 |
| **pid:[4026532547]** | 该进程所属 **PID 命名空间的 inode ID**（`readlink /proc/<pid>/ns/pid`） | 「班级编号」 |

二者不是同一类 ID：`4026532547` **不是**比 1 更大的进程号。实测 `init`(PID 1) 与 `adbd`(PID 138) 的 `ns/pid` 均为 `pid:[4026532547]`（`phase2/18-pid-namespace.txt`），说明它们在同一 Android 命名空间内。

**ReDroid 没有名为 `redroid` 的单独进程**；通常说「ReDroid 从 PID 1 起来」指 `init second_stage`（cmdline 含 `androidboot.redroid_*`）。

### 端口 ↔ PID 映射（ADB 可见部分）

| 端口 | 服务 | PID（Android 视图） | netstat | inode→PID |
|------|------|---------------------|---------|-----------|
| **5555** | adbd | **138** | `138/adbd` | ✅ 138 |
| **8886** | scrcpy-server | **3379** | `3379/app_process` | ✅ 3379 |
| **4723** | Appium | **—** | PID `-` | ❌ 无匹配 |
| **8000** | ws-scrcpy Web | **—** | PID `-` | ❌ 无匹配 |
| **8080** | Health Agent | **—** | PID `-` | ❌ 无匹配 |
| **5556** | ADB WebSocket 桥 | **—** | PID `-` | ❌ 无匹配 |
| **32001** | 未知 | **—** | PID `-` | ❌ 无匹配 |
| **49983** | envd | **无监听** | — | — |

依据：`phase2/04-netstat.txt`、`phase2/15-inode-pid-map.txt`、`phase1-live/14_cmd.txt`。

### Android / ReDroid 层关键进程（实测 PID 快照）

| 角色 | PID | 进程 | 依据 |
|------|-----|------|------|
| Android 根（ReDroid 入口） | **1** | `init` (`init second_stage`) | `phase1-live/08_cmd.txt` |
| vendor init | 3 | `init` (subcontext) | 同上 |
| 系统服务 | 253 | `system_server` | 同上 |
| 图形 | 124 | `surfaceflinger` | 同上 |
| Zygote | 158 | `zygote64` | 同上 |
| 网络 | 174 | `netd` | 同上 |
| **adbd (:5555)** | **138** | `/apex/.../adbd` | `phase1-live/15_cmd.txt` |
| **scrcpy (:8886)** | **3379** | `app_process` → `com.genymobile.scrcpy.Server` | 同上 |
| scrcpy 启动壳 | 3375 | `sh -c CLASSPATH=.../scrcpy-server.jar ...` | `phase1-live/08_cmd.txt` |
| SmartRun radio | 148 | `smartrun-radio-stub` | 同上 |
| 桌面 | 2721 | `com.android.launcher3` | 同上 |

完整进程列表见 `phase1-live/08_cmd.txt`（约 90 行）。Appium UiAutomator2 APK（`io.appium.uiautomator2.server`）探测时**未作为常驻 daemon**；仅在 Appium 建 session 后拉起，PID 不固定。

### 命名空间关系

| 进程 | PID | `ns/pid` | `ns/net` |
|------|-----|----------|----------|
| init | 1 | `pid:[4026532547]` | `net:[4026531840]` |
| adbd | 138 | `pid:[4026532547]` | `net:[4026531840]` |
| scrcpy | 3379 | （同 Android ns） | `net:[4026531840]` |
| Sidecar（Appium 等） | **不可见** | **另一 PID ns**（inode 未实测） | 共享 `net:[4026531840]` |

Sidecar 与 Android **共享网络命名空间**（故 `netstat` 能看到 4723/8000/5556），但 **不在同一 PID 命名空间**（故 `ps` / `/proc/*/fd` 找不到 sidecar 进程的 PID）。

### 结构示意（文本）

```
Cube Hypervisor MicroVM
│
├── Linux Sidecar 层
│   PID 命名空间：pid:[????????]（ADB 不可见，inode 未实测）
│   ┌─────────────────────────────────────────┐
│   │  PID ?   node (Appium)        :4723      │
│   │  PID ?   ws-scrcpy (Express)  :8000      │
│   │  PID ?   health agent         :8080      │
│   │  PID ?   ADB WebSocket 桥     :5556      │
│   └──────────────────┬──────────────────────┘
│                      │ 共享 net:[4026531840]
│                      ▼
├── Android / ReDroid 层
│   PID 命名空间：pid:[4026532547]
│   ┌─────────────────────────────────────────┐
│   │  PID 1     init            ← ReDroid 根  │
│   │  PID 138   adbd            ← :5555        │
│   │  PID 253   system_server                 │
│   │  PID 3379  app_process     ← scrcpy :8886 │
│   │  PID 2721  com.android.launcher3         │
│   │  ...                                     │
│   └─────────────────────────────────────────┘
│
└── 数据面网关（OpenResty）按端口转发，与 PID 无关
```

### 为何 netstat 里 PID 显示 `-`

Linux 的 `netstat`/`ss` 在显示监听 socket 时，若 socket 属主进程在**当前 PID 命名空间不可见**（跨 namespace），则 PID 列显示 `-`。这正是 sidecar 端口（4723/8000/8080/5556）在 `adb shell` 内的表现；而 adbd(138)、scrcpy(3379) 同属 Android ns，故可显示具体 PID。

`127.0.0.1:5037` 为**客户端侧** `adb` server（`agr mobile connect` 隧道建立后出现），不属于 ReDroid 进程树。

---

## 与探测 01 的修正

| 项 | 探测 01（2026-07-23） | 探测 02（本次） |
|----|----------|----------------------|
| 底座 | Cube VM + Redroid 14 | ✅ 一致 |
| `:4723` Appium | 实例内监听 | ✅ 一致；进一步确认 sidecar 为 Node.js |
| `:8000/:8886` scrcpy | 实例内监听 | ✅ 一致；8000=sidecar Web，8886=Android server |
| `:49983` envd | 历史报告列为监听 | ❌ **mobile 类型未暴露**；HTTPS 返回 `310508` |
| envd 进程 | 历史写「进程: adbd, Appium, envd, scrcpy」 | ❌ Android 内未找到 envd 二进制/进程 |

---

## 明确未证实项

1. **envd 是否在 mobile 沙箱 VM 内运行** — `:49983` 未暴露、ADB 内无监听；Instance Access Token 存在但不一定对应 envd HTTP 端口。
2. **Sidecar 进程的启动方式与二进制路径** — `agr instance exec` 对 mobile 失败，无法从外部 shell 进入 sidecar 层。
3. **`:32001` 用途** — 仅见监听，网关 HTTPS 返回 404。
