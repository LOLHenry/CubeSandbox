# Guest kernel 离线构建包（鲲鹏 aarch64 · 黄区）

用于在**无外网**的 openEuler / 鲲鹏上编译 CubeSandbox Android guest 内核（`CONFIG_ANDROID_BINDER_IPC`）。

## 包含内容

| 文件 | 说明 | 约大小 |
|------|------|--------|
| `linux-6.6.119.tar.xz` | 与 `configs/kernel-oc9.aarch64.config` 匹配的 stable 内核源码 | ~140MB |
| `rpms/bison-*.aarch64.rpm` | 内核 Kconfig 构建依赖 | ~1MB |
| `rpms/flex-*.aarch64.rpm` | 内核 Kconfig 构建依赖 | ~0.5MB |
| `configs/kernel-oc9.aarch64.config` | 仓库内 aarch64 guest 配置（含 Binder） | — |
| `install-guest-kernel-deps.sh` | 离线安装 bison/flex | — |
| `MANIFEST.json` | 版本与 sha256 校验 | — |

> 本包**不包含** gcc/make/openssl 等通用编译链；鲲鹏上通常已由 CubeSandbox one-click 或系统镜像提供。

## 下载（联网机 → 拷入黄区）

**推荐：GitHub Release（与 `cube-python-wheels` 相同模式）**

Release 页：`https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-guest-kernel-build-offline-aarch64`

```bash
# 联网 PC（x86 或 aarch64 均可，只下载不运行）
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-guest-kernel-build-offline-aarch64/cube-guest-kernel-build-offline-aarch64.tar.gz
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-guest-kernel-build-offline-aarch64/cube-guest-kernel-build-offline-aarch64.tar.gz.sha256
sha256sum -c cube-guest-kernel-build-offline-aarch64.tar.gz.sha256

scp cube-guest-kernel-build-offline-aarch64.tar.gz* root@<鲲鹏IP>:~/offline-pkgs/
```

**官方源（自建包时）**

| 组件 | URL |
|------|-----|
| 内核源码 | https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.119.tar.xz |
| git 备选 | `git clone --depth 1 --branch v6.6.119 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` |
| bison (openEuler 22.03 SP4 aarch64) | https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/aarch64/Packages/bison-3.8.2-2.oe2203sp4.aarch64.rpm |
| flex | https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/aarch64/Packages/flex-2.6.4-5.oe2203sp4.aarch64.rpm |

自建命令：

```bash
./deploy/one-click/scripts/one-click/build-guest-kernel-offline-bundle.sh
ls -lh deploy/one-click/dist/cube-guest-kernel-build-offline-aarch64.tar.gz*
```

## 鲲鹏上使用

```bash
cd ~/offline-pkgs
tar xzf cube-guest-kernel-build-offline-aarch64.tar.gz
cd guest-kernel-build-offline-aarch64
cat MANIFEST.json

# 1) 安装 bison/flex（若系统未装）
sudo ./install-guest-kernel-deps.sh

# 2) 解压内核源码
tar xf linux-6.6.119.tar.xz

# 3) 在 CubeSandbox 仓库根目录编译 guest 内核
cd /path/to/CubeSandbox
make guest-kernel \
  KERNEL_SRC=~/offline-pkgs/guest-kernel-build-offline-aarch64/linux-6.6.119 \
  KERNEL_TARGET_ARCH=aarch64
```

产物默认在 `_output/kernel/aarch64/vmlinux`（或 Image，取决于配置）。

## 版本对应关系

`configs/kernel-oc9.aarch64.config` 头注释为 **Linux 6.6.119**（OpenCloudOS 衍生配置），与 tarball 版本一致。不要用 6.6.69 等其它 minor 版本直接套用，除非自行 `make olddefconfig` 迁移。
