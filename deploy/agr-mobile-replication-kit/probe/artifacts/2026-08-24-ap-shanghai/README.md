# AGR Mobile 探测产物（2026-08-24）

本次在腾讯云 AGR `ap-shanghai` 对 `mobile` 类型沙箱进行的架构探测原始输出。

## 探测目标

- Instance: `qjqwkxvkjvqqqkmguqai4s6rlzfhds7rb2oajex7`
- Tool: `sdt-osj4kvz6` (`mobile-arch-probe-1787551777`)
- 分析报告: [`../../docs/AGR_ARCHITECTURE_PROBE.md`](../../docs/AGR_ARCHITECTURE_PROBE.md)

## 目录结构

```
2026-08-24-ap-shanghai/
├── README.md              # 本文件
├── instance.json          # 控制面实例/工具元数据
├── meta/
│   └── tunnel-adb-wss.log # agr mobile connect ADB WebSocket 隧道日志
├── phase0-early/          # 首轮探测（部分命令因 ADB 未就绪失败）
├── phase1-live/           # ADB 指纹采集（getprop/ps/netstat/mount）
└── phase2-detailed/       # 完整第二轮探测（端口映射/HTTPS/envd/命名空间）
```

## phase0-early/

首轮自动探测脚本输出。多数文件为 `INTERNAL_ERROR`（当时 `ADB_PATH` 未配置）。

| 文件 | 说明 |
|------|------|
| `00-connect.json` | mobile connect 失败：`ADB_NOT_FOUND` |
| `uname_-a.txt` 等 | 各 ADB 命令输出（多为错误占位） |

## phase1-live/

ADB 连通后的指纹采集（`agr instance mobile adb`）。

| 文件 | 命令 / 内容 |
|------|-------------|
| `01_cmd.txt` | getprop 构建信息 |
| `05_cmd.txt` | `netstat -lntp` 端口监听 |
| `07_cmd.txt` | `ip link` / `ip addr` |
| `08_cmd.txt` | `ps -A` 全进程列表 |
| `10_cmd.txt` | `mount` 文件系统 |
| `13_cmd.txt` | Appium 相关 APK |
| `14_cmd.txt` | adbd / scrcpy 进程 exe 路径 |
| `15_cmd.txt` | `/proc/{138,3379}/exe` 详情 |

## phase2-detailed/

完整架构探测，按编号排序。

| 文件 | 说明 |
|------|------|
| `00-connect.txt` | `agr instance mobile connect` 成功 |
| `00-adb-devices.txt` | `adb devices -l` |
| `01-uname.txt` | Guest 内核版本 |
| `02-dmi.txt` | DMI 厂商/产品（Cube Hypervisor） |
| `03-getprop-core.txt` | Redroid/SmartRun 核心属性 |
| `04-netstat.txt` | 完整端口监听表 |
| `05-mounts.txt` | overlay2 / cubebox 挂载 |
| `06-cgroups.txt` | cgroup 层级 |
| `07-port-pid-map.txt` | 首轮端口→PID 映射（失败） |
| `08-proc-grep.txt` | appium/scrcpy/adb 进程 grep |
| `09-packages.txt` | Appium APK 列表 |
| `10-find-binaries.txt` | envd/node 二进制搜索 |
| `11-curl-local.txt` | 实例内 curl（不可用） |
| `12-ns-net.txt` | net namespace 对比 |
| `13-tcp-raw.txt` | `/proc/net/tcp` 原始数据 |
| `14-tcp-full.txt` | tcp + tcp6 完整表 |
| `15-inode-pid-map.txt` | inode→PID 映射（sidecar 端口无 Android PID） |
| `16-ps-su-all.txt` | root 权限全进程列表 |
| `17-inode-fd-grep.txt` | fd socket inode 搜索 |
| `18-pid-namespace.txt` | PID/NET namespace ID |
| `19-android-fingerprint.txt` | 产品指纹 |
| `20-instance-get.json` | `agr instance get` API 响应 |
| `20-kernel-cmdline.txt` | `/proc/cmdline` |
| `21-display-props.txt` | 分辨率属性 |
| `21-tool-get.json` | `agr tool get` API 响应 |
| `30-external-https.txt` | 无 Token 外部 HTTPS 探测（全 401） |
| `31-appium-status.txt` | 无 Token Appium /status |
| `32-envd-health.txt` | 无 Token envd /health |
| `33-auth-probes.txt` | **带 Token 的完整 HTTPS 探测（核心证据）** |
| `34-8080-healthz.txt` | `:8080/healthz` |
| `34-8080-livez.txt` | `:8080/livez` |
| `35-ws-scrcpy-bundle-head.txt` | ws-scrcpy bundle.js 头部 |
| `36-scrcpy-html.txt` | ws-scrcpy HTML 页面 |
| `40-create-help.txt` | `agr instance create --help` |
| `50-instance-exec-linux.txt` | `agr instance exec` 失败记录 |
| `ARCHITECTURE-REPORT.md` | 探测摘要草稿 |

## meta/

| 文件 | 说明 |
|------|------|
| `tunnel-adb-wss.log` | `wss://5556-{instanceId}.ap-shanghai.tencentags.com/adb/ws` 隧道日志 |

## 安全说明

- 产物中**不包含** CAM SecretKey 或 Instance Access Token。
- HTTPS 探测使用 Token 鉴权，但原始文件中仅保留 URL（含 Instance ID）与响应体，未写入 Token 值。
- Instance ID 为一次性探测实例，可能已过期删除。

## 复现

```bash
export TENCENTCLOUD_SECRET_ID=...
export TENCENTCLOUD_SECRET_KEY=...
export ADB_PATH=/path/to/adb
agr config set region ap-shanghai
agr config set domain tencentags.com

# 自动化探测
./deploy/agr-mobile-replication-kit/probe/agr-probe-mobile.sh
```
