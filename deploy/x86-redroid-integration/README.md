# x86 ReDroid + CubeSandbox 集成（分步记录）

在无法访问鲲鹏黄区时，于 **x86_64 + KVM** 环境推进 ReDroid 集成。每完成一个里程碑提交一次 commit，并保留截图/日志证据。

## 虚拟化：KVM（非 PVM）

- **`CUBE_PVM_ENABLE=0`**（默认）：原生 KVM + 普通 guest kernel `vmlinux-bm`
- PVM 仅在没有 `/dev/kvm` 的 x86 备选场景使用；本路径 **不启用 PVM**
- dev-env QEMU 使用 `-enable-kvm -cpu host`；guest 内 MicroVM 依赖 nested KVM

## 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| M0 | CubeSandbox x86 one-click 安装 + smoke | 进行中 |
| M1 | 宿主机 ReDroid docker + adb | 待开始 |
| M2 | amd64 ReDroid+envd 镜像 | 待开始 |
| M3 | CubeVM 模板 E2E（tpl → READY → adb） | 待开始 |

## 推荐路径：dev-env KVM 虚机

Cloud Agent 容器缺少 `nvme-tcp` / `binder` / systemd，完整 one-click v0.7 应在 **OpenCloudOS 9 dev-env VM** 内安装：

```bash
sudo chmod 666 /dev/kvm   # 若 ubuntu 不在 kvm 组
bash deploy/x86-redroid-integration/scripts/02-dev-env-m0-bootstrap.sh
```

端口：`SSH :10022` · `CubeAPI :13000` · `WebUI :12088`

## 脚本

| 脚本 | 作用 |
|------|------|
| `00-setup-xfs-loopback.sh` | 裸金属 ext4 根盘时挂 XFS 到 `/data/cubelet` |
| `01-verify-redroid-standalone.sh` | M1：docker ReDroid + adb（需 binder） |
| `02-dev-env-m0-bootstrap.sh` | M0：prepare_image + run_vm + guest one-click |
