# x86 ReDroid + CubeSandbox 集成（分步记录）

在无法访问鲲鹏黄区时，于 **x86_64 + KVM** 环境推进 ReDroid 集成。每完成一个里程碑提交一次 commit，并保留截图/日志证据。

## 虚拟化：KVM（非 PVM）

- **`CUBE_PVM_ENABLE=0`**（默认）：原生 KVM + 普通 guest kernel `vmlinux-bm`
- PVM 仅在没有 `/dev/kvm` 的 x86 备选场景使用；本路径 **不启用 PVM**
- dev-env QEMU：Cloud Agent 内 nested KVM 不可用，默认 **`USE_TCG=1`** + OVMF；裸金属可设 `USE_TCG=0`

## 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| M0 | CubeSandbox x86 one-click 安装 + smoke | **完成**（dev-env VM 内 v0.7，`quickcheck OK`） |
| M1 | ReDroid docker + adb（guest 内需 binder 模块） | 进行中 |
| M2 | amd64 ReDroid+envd 镜像 | 待开始 |
| M3 | CubeVM 模板 E2E（tpl → READY → adb） | 待开始 |

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
| `05-guest-install-binder-modules.sh` | M1 前置：编译安装 redroid-modules（binder/ashmem） |
| `run-dev-vm-ovmf.sh` | 启动 OVMF VM（KVM 优先，TCG 回退） |

## M1 ReDroid 前置

OpenCloudOS 9 默认内核无 `binder_linux`，需先：

```bash
bash deploy/x86-redroid-integration/scripts/05-guest-install-binder-modules.sh
# 然后在 guest 内（SSH）运行 01-verify-redroid-standalone.sh
```

或在裸金属 Ubuntu 上：`apt install linux-modules-extra-$(uname -r)` + `modprobe binder_linux`。
