# AGR Mobile → CubeSandbox 鲲鹏离线复刻包

在 **离线鲲鹏 ARM64** 服务器上，复刻腾讯云 [Agent Runtime Mobile](https://cloud.tencent.com/document/product/1814/132412) 沙箱的**可控子集**（双控制面：envd + ADB），运行于自托管 [CubeSandbox](https://github.com/TencentCloud/CubeSandbox)。

> **边界说明**
> - 本包基于 **你方 2026-07-23 AGR 实测报告**（[`tencent-agent-runtime-mobile-hardware-mock.md`](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md)）与 CubeSandbox 开源能力设计。
> - **不是**腾讯云官方发布物；AGR 云端镜像（SmartRun x86_64 Android 14）与鲲鹏目标镜像（ReDroid arm64 Android 16）**底座不同**，见 `ARCHITECTURE.md`。
> - CubeSandbox **官方 upstream** 尚无 `instance_type=android` 运行时；当前复刻路径为 **`cubebox` + envd 探活 + ADB 暴露**。

---

## 1. 复刻目标对照

| AGR Mobile（云端官方） | 本包在 CubeSandbox 上的复刻 |
|------------------------|----------------------------|
| Tool 类型 `mobile` / 模板 `mobile-v1` | `tpl create-from-image` + catalog `agr-mobile-replica` |
| `agr instance mobile connect/adb` | `adb connect <node-ip>:<host_port>`（经 network-agent 映射） |
| E2B SDK `Sandbox.create()` + `_envd_access_token` | Cube SDK / E2B SDK → CubeAPI → envd `:49983` |
| 数据面 `https://{port}-{id}.{region}.tencentags.com` | CubeProxy / `get_host(port)` 或节点 `host_port` |
| Appium `:4723`、scrcpy `:8000` | **可选**（本包 v1 不内置；见 `docs/OPTIONAL_COMPONENTS.md`） |
| SmartRun x86_64 Android 14 | ReDroid **arm64** Android 16（鲲鹏 KVM） |

---

## 2. 目录结构

```
deploy/agr-mobile-replication-kit/
├── README.md                 # 本文件
├── ARCHITECTURE.md           # AGR 实测架构 + CubeSandbox 映射
├── MANIFEST.json             # 版本与依赖清单
├── configs/
│   ├── env.kunpeng.example   # 鲲鹏机环境变量模板
│   └── catalog-agr-mobile-replica.json
├── probe/                    # 连接 AGR 云端做对照探测（需凭据）
│   ├── agr-probe-mobile.sh
│   └── agr-collect-fingerprint.sh
├── scripts/
│   ├── 00-preflight.sh       # arch/kvm/docker/cubesandbox 检查
│   ├── 01-build-offline-kit.sh   # 打离线编译包（联网机构建机）
│   ├── 02-install-offline-kit.sh # 鲲鹏机解压安装
│   ├── 03-build-image.sh     # 编译 envd + 打 ReDroid 镜像
│   ├── 04-verify-image.sh    # ELF/health/adb 验证
│   ├── 05-create-template.sh # cubemastercli 建模板
│   ├── 06-run-sandbox-test.sh# 起沙箱 + envd/adb 冒烟
│   └── build-unified-tarball.sh  # 一键打完整离线 tar.gz
└── docs/
    ├── OFFLINE_KUNPENG.md    # 鲲鹏离线逐步指南
    ├── AGR_REFERENCE.md      # AGR 官方能力与端口（来自实测+文档）
    └── OPTIONAL_COMPONENTS.md
```

镜像与 envd 源码构建复用：`deploy/sandbox-images/sandbox-android-redroid-envd/offline-build-kit/`。

---

## 3. 快速开始

### 3.1 联网 arm64 构建机：打统一离线包

```bash
cd /path/to/CubeSandbox
./deploy/agr-mobile-replication-kit/scripts/build-unified-tarball.sh
# 产出：deploy/agr-mobile-replication-kit/dist/agr-mobile-replication-kit-kunpeng-arm64.tar.gz
```

### 3.2 离线鲲鹏机：安装 + 编译 + 验证

```bash
tar xzf agr-mobile-replication-kit-kunpeng-arm64.tar.gz
cd agr-mobile-replication-kit-kunpeng-arm64

cp configs/env.kunpeng.example .env
# 编辑 .env：CUBEMASTER_URL、镜像 tag 等

./scripts/02-install-offline-kit.sh
source .env
./scripts/03-build-image.sh
./scripts/04-verify-image.sh
./scripts/05-create-template.sh   # 需已安装 CubeSandbox + cubemastercli
./scripts/06-run-sandbox-test.sh
```

### 3.3 （可选）对照 AGR 云端实测

在已配置 `TENCENTCLOUD_SECRET_ID/KEY` 的机器上：

```bash
export AGR_REGION=ap-shanghai
./probe/agr-probe-mobile.sh
./probe/agr-collect-fingerprint.sh <instance-id>
```

---

## 4. 前置条件

| 组件 | 版本/要求 |
|------|-----------|
| 主机 | aarch64，OpenEuler/CentOS 等，**`/dev/kvm`** |
| CubeSandbox | one-click **v0.6.0 arm64** 已安装 |
| Docker | arm64，可 `docker load` / `docker build` |
| 内存（模板默认） | **4 CPU / 6 GiB**（ReDroid 1080p） |
| 内核 | Android guest：`CONFIG_ANDROID_BINDER_IPC`（鲲鹏 guest 内核） |
| Go（离线包内带） | 1.25.4 linux/arm64 |
| envd 源码 | e2b-dev/infra `@2026.16`（离线包 vendored） |

---

## 5. 成功标准

1. `file out/envd` → `interpreter /system/bin/linker64`（Android ELF）
2. 容器内 `GET http://127.0.0.1:49983/health` → **204**
3. `adb connect` 到映射端口，`getprop ro.build.version.release` 有输出
4. `cubemastercli tpl create-from-image` → 模板 **READY**
5. （可选）Cube SDK `commands.run` / `files.write` 经 envd 可用

---

## 6. 相关链接

- AGR 实测报告：[LOLHenry/android-cuttlefish 试验文档](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md)
- AGR 官方：[Mobile 沙箱（ADB）](https://cloud.tencent.com/document/product/1814/132412)、[手机操作 SDK](https://cloud.tencent.com/document/product/1814/127484)
- CubeSandbox：[自带镜像接入 envd](https://github.com/TencentCloud/CubeSandbox/blob/master/docs/zh/guide/tutorials/bring-your-own-image.md)
