# AGR Mobile 架构探测报告（2026-08-24 实测）

> 原始探测输出见 [`../probe/artifacts/2026-08-24-ap-shanghai/`](../probe/artifacts/2026-08-24-ap-shanghai/README.md)。

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
| 📗 历史实测 | 2026-07-23 [LOLHenry 报告](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md) |
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

与 📗 2026-07-23 历史报告 §3.1 结论一致：**Cube Hypervisor MicroVM + SmartRun/ReDroid Android 14 x86_64**，非 Cuttlefish、非经典 AVD。

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

## 与 2026-07-23 历史报告的修正

| 项 | 历史报告 | 本次 2026-08-24 实测 |
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
