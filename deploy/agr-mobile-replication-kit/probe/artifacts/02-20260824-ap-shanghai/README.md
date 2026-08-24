# 探测 02 产物 — AGR Mobile 架构（2026-08-24）

> **序号 02** · 对应报告 [`../../docs/probes/02-20260824-mobile-architecture.md`](../../docs/probes/02-20260824-mobile-architecture.md)  
> 前序产物：探测 01 正文在外部仓库，本目录无 01 产物。

本次在腾讯云 AGR `ap-shanghai` 对 `mobile` 类型沙箱进行的架构探测原始输出。

## 探测目标

- Instance: `qjqwkxvkjvqqqkmguqai4s6rlzfhds7rb2oajex7`
- Tool: `sdt-osj4kvz6` (`mobile-arch-probe-1787551777`)

## 目录结构

```
02-20260824-ap-shanghai/
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
| `33-auth-probes.txt` | **带 Token 的完整 HTTPS 探测（核心证据）** |
| `32-envd-health.txt` | envd `/health` → `310508` not configured |
| 其余 | 命名空间、inode 映射、实例 API 等 |

## meta/

| 文件 | 说明 |
|------|------|
| `tunnel-adb-wss.log` | `wss://5556-{instanceId}.ap-shanghai.tencentags.com/adb/ws` 隧道日志 |

## 安全说明

- 产物中**不包含** CAM SecretKey 或 Instance Access Token。
- Instance ID 为一次性探测实例，可能已过期删除。

## 复现

```bash
export TENCENTCLOUD_SECRET_ID=...
export TENCENTCLOUD_SECRET_KEY=...
export ADB_PATH=/path/to/adb
./deploy/agr-mobile-replication-kit/probe/agr-probe-mobile.sh
```
