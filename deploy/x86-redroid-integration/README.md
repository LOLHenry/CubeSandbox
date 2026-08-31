# x86 ReDroid + CubeSandbox 集成（分步记录）

在无法访问鲲鹏黄区时，于 **x86_64 + KVM** 环境推进 ReDroid 集成。每完成一个里程碑提交一次 commit，并保留截图/日志证据。

## 虚拟化：KVM（非 PVM）

- **`CUBE_PVM_ENABLE=0`**（默认）：原生 KVM + 普通 guest kernel `vmlinux-bm`
- PVM 仅在没有 `/dev/kvm` 的 x86 备选场景使用；本路径 **不启用 PVM**
- dev-env QEMU：Cloud Agent 内 nested KVM 不可用，默认 **`USE_TCG=1`** + OVMF；裸金属可设 `USE_TCG=0`

## 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| M0 | CubeSandbox x86 one-click 安装 + smoke | **完成** |
| M1 | ReDroid docker + adb（guest 内） | **受阻**（TCG 下 Android init 崩溃；非超时问题） |
| M2 | amd64 ReDroid+envd 镜像 | **完成**（`sandbox-android-redroid-envd:16.0.0-amd64`） |
| M3 | CubeVM 模板 E2E（tpl → READY → adb） | **部分完成**（TCG 下模板 artifact 可 READY；CubeVM 启动失败 `VmShutdown`） |

## Cloud Agent 最大化指南（无裸金属）

### 环境天花板（实测结论）

| 路径 | 结果 | 原因 |
|------|------|------|
| 宿主机直接 one-click | ❌ | 容器内 **systemd 不是 PID 1**，无法启动 unit |
| 外层 VM `USE_TCG=0`（KVM） | ❌ | 嵌套 KVM 虚机 SSH 不通 |
| 外层 VM `USE_TCG=1`（TCG）+ M0/M2/M3 artifact | ✅ | 控制面 + 镜像解包可用 |
| 内层 CubeVM（M3 CREATING_TEMPLATE） | ❌ | **VmExit::Reset**（alpine 也失败，非 Android 专属） |
| M1 ReDroid docker | ❌ | `init: Failed to initialize property area` |

**结论**：Cloud Agent 上可稳定交付 **M0 + M2 + M3 前半段（artifact READY）**；完整 **CubeVM 沙箱 / ReDroid boot** 需要真实 KVM 宿主机（非嵌套 TCG）。

一键跑最大可用路径：

```bash
bash deploy/x86-redroid-integration/scripts/10-cloud-agent-maximum.sh
```

## 推荐路径：dev-env KVM 虚机

Cloud Agent 容器缺少 `nvme-tcp` / `binder` / systemd，完整 one-click v0.7 应在 **OpenCloudOS 9 dev-env VM** 内安装：

```bash
sudo chmod 666 /dev/kvm   # 若 ubuntu 不在 kvm 组
USE_TCG=1 VM_MEMORY_MB=8192 bash deploy/x86-redroid-integration/scripts/03-dev-env-provision-and-install.sh
```

**注意**：one-click 预检要求 guest **≥7GB RAM**，默认 `VM_MEMORY_MB=8192`。

端口：`SSH :10022` · `CubeAPI :13000` · `WebUI :12088`

## 脚本

| 脚本 | 作用 |
|------|------|
| `00-setup-xfs-loopback.sh` | 裸金属 ext4 根盘时挂 XFS 到 `/data/cubelet` |
| `01-verify-redroid-standalone.sh` | M1：docker ReDroid + adb（需 binder） |
| `02-dev-env-m0-bootstrap.sh` | M0 旧路径（prepare_image + run_vm） |
| `03-dev-env-provision-and-install.sh` | **M0 主路径**：OVMF/TCG VM + guest provision + one-click |
| `04-guest-oneclick-install.sh` | 在已 provision 的 guest 内单独跑 one-click |
| `05-guest-install-binder-modules.sh` | M1 可选：编译 redroid-modules（OpenCloudOS 已内置 binder） |
| `05b-guest-load-ashmem.sh` | M1 前置：编译加载 ashmem_linux（OpenCloudOS 6.6） |
| `06-guest-verify-redroid.sh` | M1：guest 内 ReDroid + adb 验证 |
| `07-build-amd64-redroid-envd.sh` | M2：构建 amd64 envd 镜像（需 NDK+CGO） |
| `08-guest-e2e-template.sh` | M3：导入镜像 + template from-image E2E |
| `09-export-amd64-offline-bundle.sh` | 导出 amd64 离线 docker 包（上传 GitHub Release） |
| `run-dev-vm-ovmf.sh` | 启动 OVMF VM（KVM 优先，TCG 回退） |

## M1 ReDroid 前置

OpenCloudOS 9 默认内核无 `binder_linux`，需先：

```bash
bash deploy/x86-redroid-integration/scripts/05-guest-install-binder-modules.sh
# 然后在 guest 内（SSH）运行 01-verify-redroid-standalone.sh
```

或在裸金属 Ubuntu 上：`apt install linux-modules-extra-$(uname -r)` + `modprobe binder_linux`。

## M2 离线包（GitHub Release）

amd64 `sandbox-android-redroid-envd` 镜像已导出为离线 docker 包，避免云端环境重置后需重新构建（约 702MB）：

- **Release tag**: [`x86-redroid-amd64-envd-m2-preview`](https://github.com/LOLHenry/CubeSandbox/releases/tag/x86-redroid-amd64-envd-m2-preview)
- **文件**: `cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz` + `.sha256`

```bash
# 下载并加载（裸金属 x86_64 + Docker）
gh release download x86-redroid-amd64-envd-m2-preview \
  -p 'cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz*'
sha256sum -c cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz.sha256
gunzip -c cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz | docker load
# → Loaded image: sandbox-android-redroid-envd:16.0.0-amd64
```

本地重新导出：

```bash
bash deploy/x86-redroid-integration/scripts/09-export-amd64-offline-bundle.sh
# BUILD_IMAGE=1 会先执行 07-build-amd64-redroid-envd.sh
```
