# 鲲鹏 920B（ARM64）部署与调用手册

本文记录在 **鲲鹏 / aarch64** 上部署 CubeSandbox v0.6.0 的实操步骤：已完成事项、下一步、以及启动后如何调用接口创建沙箱。

> 官方通用文档见：[裸金属 / 物理机部署](docs/zh/guide/bare-metal-deploy.md)。  
> 下文中「离线 Docker 镜像包」是网络访问 TCR 失败时的补充流程，**不在官方文档主路径里**。

---

## 0. 环境前提（请先确认）

| 项 | 要求 |
|---|---|
| CPU | aarch64（`uname -m` → `aarch64`） |
| KVM | `/dev/kvm` 存在 |
| Docker | 已安装并运行（arm64 Engine） |
| 内存 | ≥ 8 GB |
| `/data/cubelet` | 必须在 **XFS** 上（可用独立 XFS 盘或 loopback） |
| glibc | ≥ 2.31 |
| 架构注意 | **不要用 PVM**（PVM 仅 x86_64）；用原生 KVM + arm64 one-click 包 |

自检：

```bash
uname -m
ls -la /dev/kvm
docker info >/dev/null && echo docker_ok
df -T /data/cubelet 2>/dev/null || df -T /
getconf PAGE_SIZE   # 4096 或 65536 均可（建议 CubeSandbox ≥ 0.5.1）
```

---

## 1. 已完成 / 应完成的操作（按顺序）

### 1.1 下载并解压 one-click 发布包（ARM64）

从 Release 下载（不要下 Source code，不要下 amd64）：

```text
cube-sandbox-one-click-v0.6.0-arm64.tar.gz
```

- GitHub：https://github.com/TencentCloud/CubeSandbox/releases  
- CNB（国内）：https://cnb.cool/CubeSandbox/CubeSandbox/-/releases  

```bash
tar -xzf cube-sandbox-one-click-v0.6.0-arm64.tar.gz
cd cube-sandbox-one-click-v0.6.0-arm64
ls -l install.sh assets/package/sandbox-package.tar.gz
```

两个文件都必须存在。若只有源码树里的 `deploy/one-click/install.sh` 而没有 `assets/package/sandbox-package.tar.gz`，说明下错包了。

### 1.2 配置 `.env`

```bash
cp env.example .env
```

至少设置：

```bash
MIRROR=cn
# 若主网卡不是 eth0，再设置：
# CUBE_SANDBOX_NODE_IP=<本机IP>
```

说明：有两份配置，建议**两边写同样的关键项**：

| 文件 | 路径 | 作用 |
|------|------|------|
| 安装包 `.env` | one-click 解压目录下的 `.env` | `install.sh` / 升级重装时读；写这里防重装丢失 |
| 运行时 `.one-click.env` | `/usr/local/services/cubetoolbox/.one-click.env` | systemd 真正加载；改完需 `systemctl restart` 才生效 |

鲲鹏离线场景建议两边都包含：

```bash
MIRROR=cn
# CUBE_SANDBOX_NODE_IP=<本机业务网卡 IP>   # 主网卡不是 eth0 时必填
CUBE_PROXY_DNSMASQ_MODE=standalone         # DNS 踩坑时；默认 networkmanager
CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false  # 离线本地模板必填，见 §2.0
```

### 1.3 离线导入 Docker 镜像（本机拉 TCR 超时时必做）

**背景：**

- 安装会 `docker pull` MySQL / Redis / CoreDNS / OpenResty / cube-proxy / cube-lifecycle-manager / cube-egress 等。
- 鲲鹏访问 TCR 常出现：`client.timeout exceeded while awaiting headers`。
- `cube-sandbox-cn` 上 **cube-proxy / cube-lifecycle-manager / cube-egress 的 `:v0.6.0` 目前是单架构 amd64**；真正的 arm64 在 **int 多架构仓**。错误导入 amd64 会出现：  
  `requested image's platform (linux/amd64) does not match the detected host platform`。

离线包（已校验 **全部 linux/arm64**）Release：

https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-docker-arm64-v0.6.0

包 sha256：

```text
1de08ed0d20d5eaefa0f958b3f64625a9a2c91310f871c42b679139d6649956b
```

```bash
# 下载后校验
sha256sum cube-sandbox-docker-arm64-v0.6.0.tar.gz

tar -xzf cube-sandbox-docker-arm64-v0.6.0.tar.gz
cd cube-sandbox-docker-arm64-v0.6.0

# 若之前 load 过错误的 amd64 组件镜像，先删掉
docker rmi -f $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'cube-egress|cube-proxy|lifecycle') 2>/dev/null || true

sudo bash ./load-images.sh

# 必须看到 arm64
docker image inspect \
  cube-sandbox-int.tencentcloudcr.com/cube-sandbox/cube-egress:v0.6.0 \
  --format '{{.Architecture}}'
```

`load-images.sh` 会把 int 的 arm64 镜像同时 tag 成 cn 名，便于 `MIRROR=cn` 离线使用。

> **Android 沙箱（ReDroid）** 的 workload 镜像**不在**上述 one-click 组件包里，需单独下载 §2.4 的 Android 离线包。

### 1.4 运行安装

回到 one-click 目录：

```bash
cd /path/to/cube-sandbox-one-click-v0.6.0-arm64
sudo bash ./install.sh
```

成功标志：

```text
[quickcheck] OK
[one-click] install complete (role=control)
```

若卡在 `Created symlink ... cube-sandbox-control.target` 之后：多半在 `systemctl enable --now` 等 Docker/服务；另开终端：

```bash
systemctl list-jobs
systemctl list-units 'cube-sandbox-*' --no-pager
systemctl --failed --no-pager
docker ps -a
journalctl -u cube-sandbox-cube-egress.service -n 80 --no-pager
```

若服务已部分安装，可：

```bash
# 确保运行配置
grep MIRROR /usr/local/services/cubetoolbox/.one-click.env
# 应为 MIRROR=cn

sudo systemctl restart cube-sandbox-control.target
sudo /usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh
```

注意：`systemctl restart xxx` 在 `docker pull` 超时未完成前会长时间阻塞；先保证本地已有 **正确 arch 的同名镜像**。

安装后自检：

```bash
systemctl is-active cube-sandbox-control.target
ss -lntp | grep -E '3000|8089|9999'
docker ps
```

---

## 2. 下一步：制作模板（`install complete` 之后）

平台起来后还没有可启动的沙箱模板。

### 2.0 必做：关闭 native 远程导出（否则必走外网）

v0.6 默认开启 **native rootfs export**，会**忽略本地 Docker 镜像**，始终访问远程 registry。  
短名 `sandbox-code:latest` 会被当成 Docker Hub：

```text
native export failed to resolve image sandbox-code:latest
get https://index.docker.io/v2/... dial tcp ... i/o timeout
```

这是 **联网解析失败**，不是镜像平台（arm64/amd64）不匹配。平台不匹配一般写作  
`requested image's platform (linux/amd64) does not match ...`。

```bash
ENV=/usr/local/services/cubetoolbox/.one-click.env
grep -q '^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=' "$ENV" \
  && sudo sed -i 's/^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=.*/CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false/' "$ENV" \
  || echo 'CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false' | sudo tee -a "$ENV"

grep NATIVE "$ENV"
# 必须：CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false

# 不重启不生效
sudo systemctl restart cube-sandbox-cubemaster.service
systemctl is-active cube-sandbox-cubemaster.service

# 可选：确认进程已带上变量
sudo tr '\0' '\n' < /proc/$(pidof cubemaster)/environ | grep NATIVE
```

one-click 解压目录的 `.env` 也建议写上同一行，避免以后升级/重装丢掉。

> 若机器上同时有 `skopeo` **和** `umoci`，关掉 native 后仍可能走 dockerless 远程路径。  
> 离线场景确认：`command -v umoci` 若存在，可临时 `sudo mv $(command -v umoci) $(command -v umoci).bak` 再重启 cubemaster。

### 2.1 确认离线包已导入 sandbox-code（arm64）

```bash
docker images | grep sandbox-code
docker image inspect \
  cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest \
  --format '{{.Architecture}}'
# 期望：arm64（鲲鹏主机 uname -m 为 aarch64）
```

若没有，回到离线包目录再执行一次 `sudo bash ./load-images.sh`。

### 2.2 打成本地短名字

```bash
docker tag \
  cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest \
  sandbox-code:latest

docker image inspect sandbox-code:latest --format '{{.Id}} {{.Architecture}}'
```

### 2.3 用本地名创建模板

须在完成 **§2.0**（native=false + 重启 cubemaster）之后：

```bash
cubemastercli tpl create-from-image \
  --image sandbox-code:latest \
  --writable-layer-size 1G \
  --expose-port 49999 \
  --expose-port 49983 \
  --probe 49999
```

```bash
cubemastercli tpl watch --job-id <job_id>
```

等到 **`READY`**，记下 **`template_id`**。

成功时日志里**不应再出现** `index.docker.io` 或 `native export failed to resolve`。

> 仅当本机能稳定访问镜像仓库时，才可保持 native 默认开启，并直接使用  
> `--image cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest`。

### 2.4 Android 沙箱（鲲鹏 · ReDroid AOSP 16，预览）

one-click arm64 发布包附带 catalog：`assets/sandbox-catalog/sandbox-android-kunpeng-arm64.json`（亦写入 `release-manifest.json` 的 `sandbox_catalog`）。

**官方镜像（arm64）：**

```text
cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64
cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64
sandbox-android-redroid:16.0.0-arm64
```

上游 workload：`redroid/redroid:16.0.0_64only-latest`（AOSP 16）。封装 Dockerfile 见 `deploy/sandbox-images/sandbox-android-redroid/`。

> **状态说明**：catalog 与离线包已就绪；`instance_type=android` 运行时（Android guest Binder 内核、`androidcbri`、模板 `boot_completed` 探针）仍在开发中，当前为**预览**。

#### 2.4.1 黄区离线包（推荐：直接下载 Release）

**预览 Release（已构建、可下载）：**

https://github.com/LOLHenry/CubeSandbox/releases/tag/android-kunpeng-arm64-preview

| 资产 | 说明 |
|------|------|
| `cube-sandbox-android-kunpeng-arm64-docker-preview.tar.gz` | 离线 Docker 镜像包（含 CN / INT / local 三个 tag） |
| `cube-sandbox-android-kunpeng-arm64-docker-preview.tar.gz.sha256` | 校验文件 |

包 sha256（2026-08-14 构建）：

```text
2780df92a4bda72952c1453663fa7e41ed1a66243df11bb8e43b9b782fe86886
```

鲲鹏目标机加载：

```bash
# 下载 preview 包与 .sha256 后
sha256sum -c cube-sandbox-android-kunpeng-arm64-docker-preview.tar.gz.sha256
gunzip -c cube-sandbox-android-kunpeng-arm64-docker-preview.tar.gz | docker load

# 必须看到 arm64（不是 amd64）
docker image inspect \
  cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64 \
  --format '{{.Architecture}}'
```

**正式版 Release**（打 `v*` tag 后由 CI 自动上传，资产名与 tag 对齐）：

```text
cube-sandbox-android-kunpeng-arm64-docker-v0.6.0.tar.gz
cube-sandbox-android-kunpeng-arm64-docker-v0.6.0.tar.gz.sha256
```

加载方式同上，把文件名中的 `preview` 换成对应版本号即可。

**envd 版离线包（推荐用于当前 cubebox 模板路径）**

| 资产 | 说明 |
|------|------|
| `cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview5.tar.gz` | **推荐**：双通道 + 恢复 preview2 同款 shell 入口（模板探活已通过） |
| `cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview4.tar.gz` | 使用 `envd-starter`，鲲鹏上模板探活易失败，勿用 |
| `cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview3.tar.gz` | 同上（`envd-starter` 回归） |
| `cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview5.tar.gz.sha256` | 校验文件 |

Release 页面：https://github.com/LOLHenry/CubeSandbox/releases/tag/android-kunpeng-arm64-envd-preview

> **双通道**：对齐腾讯云 Agent Runtime Mobile 方案——**envd :49983**（Cube SDK / 探活 / `commands.run`）+ **adbd :5555**（`adb connect` 自动化）。模板必须 **同时** `--expose-port 5555` 与 `--expose-port 49983`；从集群外访问还需 `network-agent --host-proxy-bind-ip=0.0.0.0`（见 §2.4.6）。

> **health 探活**：请使用 **`envd-preview5`**（或 **preview2**）。**preview3/preview4** 改用 `envd-starter` 作 ENTRYPOINT，鲲鹏上模板 `CREATING_TEMPLATE` 易报 `:49983 connection refused`；preview5 改回 `/system/bin/sh` + `android-redroid-entrypoint.sh`（与首次建模板成功的 preview2 相同机制），并保留双通道 EXPOSE。

包（**envd-preview5**）：

```bash
sha256sum -c cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview5.tar.gz.sha256
gunzip -c cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview5.tar.gz | docker load
```

若已加载 **preview3/preview4**，请重新 `docker load` preview5 覆盖同名 tag。

鲲鹏目标机加载后验证架构并建模板：

```bash
docker image inspect sandbox-android-redroid-envd:16.0.0-arm64 --format '{{.Architecture}}'
# 期望：arm64

cubemastercli tpl create-from-image \
  --image sandbox-android-redroid-envd:16.0.0-arm64 \
  --writable-layer-size 10Gi \
  --expose-port 5555 \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --cpu 4000 \
  --memory 6144
```

镜像 Dockerfile：`deploy/sandbox-images/sandbox-android-redroid-envd/`。构建脚本：`deploy/one-click/scripts/one-click/build-android-sandbox-envd-offline-bundle.sh`。

GitHub Actions 手动构建：仓库 → Actions → **Android Sandbox Envd Offline Bundle**（`upload_to_release` 默认上传到 `android-kunpeng-arm64-envd-preview`）。

#### 2.4.2 自行构建离线包

在 **aarch64** 构建机（或已启用 `qemu-aarch64` 的 x86_64 + Docker）上：

```bash
# 一键：构建镜像 + 导出 tar.gz + 写 sha256
RELEASE_TAG=preview BUILD_IMAGE=1 \
  ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh

# 产物默认在 deploy/one-click/dist/
ls -lh deploy/one-click/dist/cube-sandbox-android-kunpeng-arm64-docker-*.tar.gz*
```

环境变量：

| 变量 | 作用 |
|------|------|
| `RELEASE_TAG` | 输出文件名后缀（如 `preview`、`v0.6.0`） |
| `BUILD_IMAGE=1` | 先执行 `deploy/sandbox-images/sandbox-android-redroid/build.sh` |
| `ANDROID_IMAGE_TAG` | 镜像 tag，默认 `16.0.0-arm64` |
| `OUT_DIR` | 输出目录，默认 `deploy/one-click/dist` |

仅导出已有本地镜像（不重新 build）：

```bash
RELEASE_TAG=preview ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
```

**envd 版离线包**（先构建 `sandbox-android-redroid-envd` 镜像再导出）：

```bash
RELEASE_TAG=envd-preview BUILD_IMAGE=1 \
  ./deploy/one-click/scripts/one-click/build-android-sandbox-envd-offline-bundle.sh

ls -lh deploy/one-click/dist/cube-sandbox-android-kunpeng-arm64-envd-docker-*.tar.gz*
```

**GitHub Actions 远程构建**（仓库 → Actions → **Android Sandbox Offline Bundle**）：

- `release_tag`：输出文件名后缀（如 `preview`）
- `android_image_tag`：默认 `16.0.0-arm64`
- `upload_to_release`：勾选后上传到同名 GitHub Release

打正式 `v*` tag 时，`release-one-click.yml` 也会在 `ubuntu-24.04-arm` 上自动构建并上传 Android 离线包（含 **envd 版** `cube-sandbox-android-kunpeng-arm64-envd-docker-<tag>.tar.gz`）。

#### 2.4.3 制作模板

> **与官方文档的关系**：按 [自带镜像接入 (envd)](docs/zh/guide/tutorials/bring-your-own-image.md)，**当前 `cubebox` 模板流水线要求镜像内运行 `envd`（`:49983/health`）**，否则模板探活失败、SDK 的 `commands.run` / `files.*` 也无法工作。  
> 推荐使用 §2.4.1 的 **envd 离线包**（`sandbox-android-redroid-envd:16.0.0-arm64`）。纯 ReDroid 包（无 envd）仅适合预览 Android 运行时本身；若要用 `tpl create-from-image`，请用 envd 包或 §2.4.4 自行注入。  
> 目标态 `instance_type=android` 将改用 **ADB / `boot_completed` 探针**（catalog `probe_port: 5555`），届时不再强依赖 envd——该运行时仍在开发中。

在 **envd 已注入** 且平台已启用 Android guest Binder 的前提下：

> **内存 / CPU（重要）**  
> `cubemastercli tpl create-from-image` 若显式传 `--cpu` / `--memory`，默认各为 **2000**（2 核、**2000Mi ≈ 2GiB**）。  
> 对 **ReDroid AOSP 16 + 1080×1920** 在 **CubeVM** 内运行，2GiB **明显不足**（还要算上 MicroVM 内核、agent、envd、Android system_server）。  
> ReDroid 上游：约 **2GiB 为勉强下限**，**4GiB+ 推荐**；本仓库 catalog 默认 **4 核 / 6GiB**（`sandbox-android-kunpeng-arm64*.json`）。  
> **建 Android 模板时务必显式加大**，否则易出现容器 `running` 但 adbd/5555 起不来、`PORT_REFUSED`。

```bash
docker tag \
  cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64 \
  sandbox-android-redroid:16.0.0-arm64

# 推荐：4 核 + 6GiB 内存（--memory 单位为 MB，6144 = 6GiB）
cubemastercli tpl create-from-image \
  --image sandbox-android-redroid-envd:16.0.0-arm64 \
  --writable-layer-size 10Gi \
  --expose-port 5555 \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --cpu 4000 \
  --memory 6144
```

| 场景 | 建议 `--cpu` | 建议 `--memory` (MB) |
|------|-------------|----------------------|
| 最低可试（720p / 调试） | 2000 | 4096 |
| **推荐（1080×1920，catalog 默认）** | **4000** | **6144** |
| 留余量 / 多应用 | 4000–8000 | 8192 |

`tpl info <template-id>` 或 `cubemastercli info -s <sandbox-id>` 里应看到约 **4000m CPU / 6144Mi**（或你指定的值），而不是 2000Mi。

黄区若已设 `CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false`（§2.0），模板创建应使用**本地短名**，不要写远程仓库全名。

默认 ReDroid 启动参数（catalog 中 `redroid_boot_args`）：1080×1920、DPI 480、`guest` GPU 模式；ADB 端口 **5555**。

#### 2.4.4 往 ReDroid 镜像注入 envd（当前 cubebox 路径必做）

官方做法见 [bring-your-own-image.md](docs/zh/guide/tutorials/bring-your-own-image.md) §3：在 **Linux 容器**（Ubuntu 等）里从 `cubesandbox-base` 拷贝 `envd` 即可。

**ReDroid 例外**：ReDroid 用户态是 **Android / bionic**，`cubesandbox-base` 里的 `envd` 是 **`GOOS=linux`** 静态二进制，**无法在 ReDroid 内执行**。必须从 `e2b-dev/infra` 用 **`GOOS=android GOARCH=arm64`** 交叉编译 envd（本仓库 `sandbox-android-redroid-envd/Dockerfile` 已内置该步骤）。

ReDroid 自带 Android `init` 入口，不能简单 `ENTRYPOINT cube-entrypoint.sh` 覆盖。过渡做法是自定义入口脚本：**先后台启动 envd，再 exec ReDroid 原入口**。

```bash
# 推荐：直接用本仓库镜像（已编译 android/bionic envd）
./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh
# 或加载离线包 §2.4.1
```

生产入口为 **`/system/bin/sh` + `android-redroid-entrypoint.sh`**：shell 将 envd 放后台（`&`），再 `exec /init`。该方式在鲲鹏上 **模板探活已通过**；preview3/preview4 的 `envd-starter` 反而导致探活失败，已在 preview5 撤销。

```bash
# Dockerfile ENTRYPOINT（preview5）:
# ENTRYPOINT ["/system/bin/sh", "/usr/local/bin/android-redroid-entrypoint.sh"]
# 等价逻辑：
/usr/bin/envd -port 49983 >>/tmp/envd.log 2>&1 &
exec /init "$@"    # ReDroid 原入口
```

另含 `cube-envd.rc`：若早期 bootstrap 丢失，Android `post-fs-data` 会再次拉起 envd。

构建并验证 envd（在 **鲲鹏 aarch64** 上执行）：

```bash
docker build --platform linux/arm64 -t sandbox-android-redroid-envd:16.0.0-arm64 \
  deploy/sandbox-images/sandbox-android-redroid-envd

docker run -d --privileged --name redroid-test sandbox-android-redroid-envd:16.0.0-arm64

# 1) 确认是 Android 链接的 envd（应看到 interpreter /system/bin/linker64）
docker exec redroid-test file /usr/bin/envd

# 2) 确认进程在跑
docker exec redroid-test ps -A | grep envd

# 3) HTTP 探针（ReDroid 通常无 curl，用 toybox wget）
docker exec redroid-test toybox wget -q -O /dev/null http://127.0.0.1:49983/health && echo "envd OK"
# 期望：envd OK（对应 HTTP 204）
```

本地验证通过后再执行 §2.4.3 的 `tpl create-from-image`。

#### 2.4.5 模板探活失败：`:49983 connection refused`

若 `tpl create-from-image` / `tpl image-job` 报错类似：

```text
template tpl-xxx creation failed: Get "http://192.168.0.x:49983/health":
dial tcp 192.168.0.x:49983: connect: connection refused
```

表示模板构建沙箱内 **49983 无进程监听**。按下面顺序排查：

| 步骤 | 命令 / 检查 | 说明 |
|------|-------------|------|
| 1 | `file /usr/bin/envd`（容器内） | 必须是 **Android** ELF（`interpreter /system/bin/linker64`）。若是 `statically linked` 且 `GOOS=linux`，说明用了错误离线包，需 **重新构建/加载 §2.4.1 envd 包** |
| 2 | `cat /tmp/envd.log` 或 `cat /data/local/tmp/envd.log` | envd 启动失败原因（权限、端口占用等） |
| 3 | `ps -A \| grep envd` | 无进程 → 入口脚本未跑或 envd 秒退；**preview3/4（envd-starter）** 易现此问题，请换 **preview5** 或 **preview2** |
| 4 | `tpl create-from-image` 加 `--cpu 4000 --memory 6144` | 默认 2GiB 时 Android 可能起不来，但 **49983 refused 通常是 envd 二进制不对** |
| 5 | 模板构建日志 | `ls /data/log/template/<template_id>/` 或 `cubemastercli tpl image-job <job_id>` |

**修复后重新建模板**（务必带资源与探针）：

```bash
cubemastercli tpl create-from-image \
  --image sandbox-android-redroid-envd:16.0.0-arm64 \
  --writable-layer-size 10Gi \
  --expose-port 5555 \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --cpu 4000 \
  --memory 6144
```

旧模板 `tpl-a433b11ce5c748fc8184fc6a` 可删除后重建：`cubemastercli tpl delete tpl-a433b11ce5c748fc8184fc6a`（若 CLI 支持）或控制台清理 FAILED 模板。

#### 2.4.6 外部打通 envd + ADB 双通道

参考 [腾讯云 Agent Runtime Mobile 试验](https://github.com/LOLHenry/android-cuttlefish/blob/main/docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md)：Android 沙箱采用 **双控制面**——与商用 Mobile 沙箱一致。

| 通道 | 容器端口 | 用途 |
|------|----------|------|
| **envd** | `49983` | 模板探活 `GET /health`、Cube SDK `commands.run` / `files.*` |
| **ADB (adbd)** | `5555` | `adb connect <host>:<port>` 自动化、UI 探测、`getprop` 等 |

**1. 模板必须暴露两个端口**（`--probe` 仍指向 envd，ADB 不参与探活）：

```bash
cubemastercli tpl create-from-image \
  --image sandbox-android-redroid-envd:16.0.0-arm64 \
  --writable-layer-size 10Gi \
  --expose-port 5555 \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --cpu 4000 \
  --memory 6144
```

**2. network-agent 绑定到所有网卡**（默认 `127.0.0.1` 仅本机可连映射端口）：

```bash
# 编辑 /usr/local/services/cubetoolbox/scripts/systemd/network-agent-start.sh
# 在 exec 行前增加 --host-proxy-bind-ip=0.0.0.0，例如：
exec "${NETWORK_AGENT_BIN}" \
  --cubelet-config "${CUBELET_CONFIG}" \
  --state-dir "${NETWORK_AGENT_STATE_DIR}" \
  --host-proxy-bind-ip=0.0.0.0

sudo systemctl restart cube-sandbox-network-agent.service
```

**3. 防火墙**：放行 network-agent 分配的 **host_port**（非固定 5555/49983；每个沙箱动态映射）。

**4. 创建沙箱后查映射端口**：

```bash
cubemastercli info -s <sandbox_id>
# 在 port_mappings 中找 container_port=5555 / 49983 对应的 host_port
```

**5. 从外部验证**：

```bash
# envd 探活（host_port 替换为映射值）
curl -s -o /dev/null -w "%{http_code}\n" "http://<节点IP>:<envd_host_port>/health"
# 期望 204

# ADB（需本机安装 platform-tools）
adb connect <节点IP>:<adb_host_port>
adb -s <节点IP>:<adb_host_port> shell getprop ro.hardware.gralloc
# 期望包含 redroid
```

**6. 本地镜像自检**（鲲鹏 aarch64 上，privileged + 发布端口）：

```bash
./deploy/sandbox-images/sandbox-android-redroid-envd/verify-envd-health.sh
# 依次检查 envd ELF、:49983/health、:5555 adbd；可选 adb connect
```

常见 **ADB `PORT_REFUSED`**：模板只暴露了 `49983` 未暴露 `5555`、内存不足（<6GiB）、Android 尚未 boot_completed、或 `host-proxy-bind-ip` 仍为 `127.0.0.1` 却从其他机器访问。

---

## 3. 启动后：如何调用接口创建 / 使用沙箱

CubeAPI 默认监听：**`http://<节点IP>:3000`**（本机可用 `127.0.0.1`）。

### 3.1 环境变量（SDK / 客户端通用）

```bash
export E2B_API_URL="http://127.0.0.1:3000"
export E2B_API_KEY="e2b_000000"          # 本地任意非空即可
export CUBE_TEMPLATE_ID="<你的 template_id>"
export SSL_CERT_FILE="/root/.local/share/mkcert/rootCA.pem"
```

| 变量 | 作用 |
|------|------|
| `E2B_API_URL` | 指向本机 CubeAPI，而不是 E2B 公有云 |
| `E2B_API_KEY` | SDK 要求非空；未开鉴权时可填占位 |
| `CUBE_TEMPLATE_ID` | 上一步模板 ID |
| `SSL_CERT_FILE` | 访问沙箱 HTTPS（via cube-proxy / `*.cube.app`）时需要 |

### 3.2 模板能力说明（`sandbox-code`）

用 `sandbox-code:latest` + 暴露 `49999/49983` 做成的模板是 **Code Interpreter** 能力（沙箱内 Jupyter / CI gateway），不是 CLI 里名叫 `code_interpreter` 的字段；`instance-type` 仍是默认 `cubebox`。

客户端用 `e2b_code_interpreter` 的 `run_code`（或示例里的 `E2BSandboxType.CODE_INTERPRETER`）才是在用这条能力。

**不要默认认为已带数据科学栈。** `sandbox-code` 主要是代码解释器运行时；官方数据分析示例常用另一张镜像  
`cube-sandbox-image.tencentcloudcr.com/demo/e2b-code-interpreter:v1.1-data`  
（pandas / numpy / matplotlib 等）。且目前文档明确 Multi-Arch 的是 `sandbox-code`；`v1.1-data` 在鲲鹏上可能是 amd64，需自行确认。

用下面 §3.3 的探测脚本在沙箱内验证包是否存在。

### 3.3 方式 A：Python SDK（推荐；这也是「进入沙箱」的方式）

一般**不 SSH 进 MicroVM**，而是在客户端用 SDK 远程执行：`run_code` / `commands.run` 即在沙箱内运行。

```bash
pip install e2b-code-interpreter
# 或按文档使用 cubesandbox SDK；代码解释器场景常用 e2b-code-interpreter
```

```python
import os
from e2b_code_interpreter import Sandbox

with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"]) as sandbox:
    result = sandbox.run_code(
        "import platform; print(platform.machine())"
    )
    print(result)
    # 鲲鹏上预期输出包含：aarch64
```

探测数据科学包（True=已装，False=没有）：

```python
import os
from e2b_code_interpreter import Sandbox

with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"]) as sbx:
    print("sandbox_id =", sbx.sandbox_id)
    r = sbx.run_code(
        "import importlib.util as u\n"
        "for m in ['numpy','pandas','matplotlib','sklearn']:\n"
        "    print(m, bool(u.find_spec(m)))\n"
    )
    print(r)
```

也可用 Shell（不经 Jupyter）：

```python
with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"]) as sbx:
    print(sbx.commands.run("uname -m").stdout)
    print(sbx.commands.run("python3 -c 'import sys; print(sys.version)'").stdout)
```

创建沙箱（只要 ID、自行管理生命周期）：

```python
import os
from e2b_code_interpreter import Sandbox

sbx = Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"])
print("sandbox_id =", sbx.sandbox_id)
# ... 使用 sbx ...
sbx.kill()
```

### 3.4 方式 B：HTTP REST（兼容 E2B）

健康检查：

```bash
curl -sS "http://127.0.0.1:3000/health"
```

创建沙箱：

```bash
curl -sS -X POST "http://127.0.0.1:3000/sandboxes" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: ${E2B_API_KEY}" \
  -d "{
    \"templateID\": \"${CUBE_TEMPLATE_ID}\"
  }"
```

响应里会包含沙箱 ID（字段名以实际 JSON 为准，常见为 `sandboxID` / `clientID` 等）。

列出 / 删除示例：

```bash
# 按实际 OpenAPI 路径调整；常用：
curl -sS "http://127.0.0.1:3000/sandboxes" \
  -H "X-API-KEY: ${E2B_API_KEY}"

curl -sS -X DELETE "http://127.0.0.1:3000/sandboxes/<sandbox_id>" \
  -H "X-API-KEY: ${E2B_API_KEY}"
```

在沙箱内执行代码（代码解释器模板，Jupyter 端口 49999；也可用 SDK 的 `run_code`）：

```bash
# 通过 cube-proxy 域名访问沙箱端口（需 DNS/hosts 能解析 *.cube.app）
# 或使用 SDK，避免手写端口转发细节
```

WebUI（若已启动）默认：`http://<节点IP>:12088`

### 3.5 调用链（便于理解）

```text
客户端 / SDK / curl
  → CubeAPI :3000          （创建沙箱等控制面 API）
    → CubeMaster           （调度）
      → Cubelet            （本机拉起 MicroVM）
  → CubeProxy / *.cube.app （访问沙箱内服务端口；Host 头路由到具体沙箱）
```

**DNS 说明：** `*.cube.app` 是集群私有域名，one-click 已在鲲鹏本机配好 CoreDNS/dnsmasq。  
**推荐路线：在鲲鹏本机跑客户端**（同机 DNS 已通，无需 hosts / WSL / `CUBE_PROXY_NODE_IP`）。  
鲲鹏通常**无公网**，依赖包需在联网机下载后**离线安装**（§3.6）。

建议顺序：

1. 离线装 Python + `e2b-code-interpreter`
2. 先跑官方 **`code-sandbox-quickstart`**（验证控制面 / 数据面）
3. 再离线装 **OpenClaw**，跑 **`openclaw-integration`**

> `CUBE_PROXY_NODE_IP` 仅 **`cubesandbox`** SDK 支持；官方示例用的是 **`e2b-code-interpreter`**，同机跑即可直接解析 `*.cube.app`。

### 3.6 鲲鹏本机演示（离线装包 → quickstart → OpenClaw）

架构：

```text
鲲鹏本机
  ├─ CubeSandbox（已装）── DNS 已解析 *.cube.app
  ├─ Python venv + e2b-code-interpreter   ← 离线 wheel（先做）
  │     └─ examples/code-sandbox-quickstart   ← 第一段演示
  └─ Node.js + OpenClaw + cube-sandbox skill ← 离线 tar（后做）
        └─ examples/openclaw-integration      ← 第二段演示
```

官方示例（不另造 demo）：

1. [`examples/code-sandbox-quickstart/README_zh.md`](examples/code-sandbox-quickstart/README_zh.md) — **先做**
2. [`examples/openclaw-integration/README_zh.md`](examples/openclaw-integration/README_zh.md) — **后做**

#### 3.6.1 离线包清单（联网机下载 → 拷到鲲鹏）

在一台**能访问公网**的机器上准备下列文件，再 `scp` / U 盘拷到鲲鹏（例如 `~/offline-pkgs/`）。

| 阶段 | 包 | 用途 | 架构注意 |
|------|----|------|----------|
| ① 先做 quickstart | `cube-python-wheels-py312-aarch64.tar.gz` | 预打包 Release 或自建的 `quickstart-pkgs/` | **aarch64 / cp312**；推荐 §3.6.1-A0 |
| ② 再做 OpenClaw | `node-*-linux-arm64.tar.xz` | Node 运行时（OpenClaw 依赖） | **linux-arm64**，Node **22+** |
| ② | `openclaw-bundle-linux-arm64.tar.gz` | 从未装过 OpenClaw 时用的完整离线包 | 必须在 **aarch64 Linux** 上打包 |

**Python wheels 推荐**：直接下载 [GitHub Release 预打包](https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64)（x86 PC 即可，含 `pyqwest` aarch64 wheel）。  
若需自建：联网机建议 **aarch64 Linux**（另一台鲲鹏临时开网、云 ARM VM 等）；x86 见 §3.6.1-A1。  
**OpenClaw 的 npm bundle 不要在 x86 上打**（`sharp` 等原生模块与 CPU 绑定）。

在鲲鹏上确认 Python（建议 3.12）：

```bash
python3 --version
# 若无 3.12：用系统包管理器安装 python3.12 / python3.12-venv（离线 rpm/deb 另备）
```

##### A. 阶段①：Python wheels（给 quickstart 用）

> **若鲲鹏上 proxy / 国内镜像都拉不到包**：不要在服务器上 `pip install`。  
> 在**另一台能访问公网的机器**上下载完整 wheel 包，再 `scp` / U 盘拷到鲲鹏 `~/offline-pkgs/`。

`pip download` 会**自动拉传递依赖**（约 25～30 个 wheel）。其中 **`pyqwest`**、**`protobuf-py-ext`**
是 **aarch64 原生包**，缺了或下成 x86_64 时，鲲鹏离线安装会报：

```text
No matching distribution found for pyqwest
```

**A0. 推荐：直接下载预打包 Release（x86 PC 即可）**

本仓库已在 GitHub Release 发布完整 wheel 包（x86 联网机交叉下载，含 **aarch64 cp312** 的 `pyqwest` / `protobuf-py-ext`）：

| 文件 | sha256 |
|------|--------|
| [`cube-python-wheels-py312-aarch64.tar.gz`](https://github.com/LOLHenry/CubeSandbox/releases/download/cube-python-wheels-py312-aarch64/cube-python-wheels-py312-aarch64.tar.gz) | `80c9ccd582cec6ecdca3c10f4b61215ee162f7f8c7c35e6f44d6461a947293fb` |

Release 页：https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64

**在联网 PC 上下载并拷到鲲鹏：**

```bash
# 联网 PC（x86 或 aarch64 均可）
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-python-wheels-py312-aarch64/cube-python-wheels-py312-aarch64.tar.gz
sha256sum cube-python-wheels-py312-aarch64.tar.gz
# 期望：80c9ccd582cec6ecdca3c10f4b61215ee162f7f8c7c35e6f44d6461a947293fb

scp cube-python-wheels-py312-aarch64.tar.gz root@<鲲鹏IP>:~/offline-pkgs/
```

**鲲鹏上安装**（需先按 §3.6.4 建好 Python 3.12 venv）：

```bash
cd ~/offline-pkgs
tar xzf cube-python-wheels-py312-aarch64.tar.gz

export PATH="/usr/local/python3.12/bin:$PATH"   # 若 make altinstall
python3.12 -m venv ~/cube-demo/.venv
source ~/cube-demo/.venv/bin/activate

bash install-e2b-offline.sh
# 或手动：
# pip install --no-index --find-links=./quickstart-pkgs/ \
#   e2b-code-interpreter python-dotenv rich

python -c "import e2b_code_interpreter; print('ok', e2b_code_interpreter.__version__)"
```

也可从仓库 [`offline-pkgs/`](offline-pkgs/) 目录取同名 tar（内容与 Release 一致）。

**A1. 自建：x86 联网机交叉下载**

无 Release 或需更新版本时，在 **x86 + Python 3.12** 上执行（与预打包命令一致）：

```bash
rm -rf quickstart-pkgs && mkdir -p quickstart-pkgs

python3.12 -m pip download e2b-code-interpreter python-dotenv rich \
  --platform manylinux2014_aarch64 \
  --platform linux_aarch64 \
  --python-version 312 --implementation cp --abi cp312 \
  --only-binary=:all: \
  -i https://pypi.org/simple \
  -d ./quickstart-pkgs/

# 必检
ls quickstart-pkgs | grep -E 'pyqwest|protobuf_py_ext'
ls quickstart-pkgs | grep x86_64 && echo "ERROR: wrong arch" || echo "arch ok"
ls quickstart-pkgs/*.whl | wc -l    # 通常 > 20

tar czf cube-python-wheels-py312-aarch64.tar.gz quickstart-pkgs
scp cube-python-wheels-py312-aarch64.tar.gz root@<鲲鹏IP>:~/offline-pkgs/
```

**A2. 自建：联网 aarch64 或 Docker arm64**

有 **真 aarch64 + Python 3.12** 时可直接下载（不必加 `--platform`）：

```bash
uname -m          # 必须 aarch64
python3.12 -V

rm -rf quickstart-pkgs && mkdir -p quickstart-pkgs
python3.12 -m pip download \
  e2b-code-interpreter python-dotenv rich \
  -i https://pypi.org/simple \
  -d ./quickstart-pkgs/

ls quickstart-pkgs | grep pyqwest
tar czf cube-python-wheels-py312-aarch64.tar.gz quickstart-pkgs
```

**下载机没有 aarch64 时**：用 Docker 在 x86 宿主机上模拟 arm64 下载：

```bash
docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -w /work python:3.12-bookworm bash -lc '
    pip download e2b-code-interpreter python-dotenv rich \
      -i https://pypi.org/simple -d ./quickstart-pkgs
    ls quickstart-pkgs | grep pyqwest
    tar czf cube-python-wheels-py312-aarch64.tar.gz quickstart-pkgs
  '
```

若已有目录但只缺 `pyqwest`，可在联网机上补下后拷进同一 `quickstart-pkgs/`：

```bash
python3.12 -m pip download pyqwest protobuf-py-ext \
  --platform manylinux2014_aarch64 --python-version 312 \
  --implementation cp --abi cp312 --only-binary=:all: \
  -d ./quickstart-pkgs/
```

##### B. 阶段②：OpenClaw 离线下载（从未安装过时按此做）

OpenClaw 是 **Node.js 全局 CLI / Gateway**（npm 包名 `openclaw`），**不是** Python 包，不能 `pip install`。  
鲲鹏无公网时，不能在鲲鹏上执行 `npm install -g openclaw` 或官方 `curl | bash` 安装脚本。

做法：在一台 **联网的 aarch64 Linux** 上装好 Node，再把 OpenClaw **连同全部依赖**打成一个 tar，拷到鲲鹏解压即用。

**B1. 下载 Node.js（linux-arm64）**

任意能上网的机器即可（浏览器或 curl）：

```bash
# 版本可换；需满足 OpenClaw 要求（官方建议 Node 22+ / 24+）
NODE_VER=v22.22.3
curl -fLO "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-arm64.tar.xz"
curl -fLO "https://nodejs.org/dist/${NODE_VER}/SHASUMS256.txt"
grep "node-${NODE_VER}-linux-arm64.tar.xz" SHASUMS256.txt | sha256sum -c -
```

把同一个 `node-*-linux-arm64.tar.xz` 拷到联网 aarch64 打包机 **和** 鲲鹏各一份。

**B2. 在联网 aarch64 上临时解压 Node，用于打包 OpenClaw**

```bash
mkdir -p "$HOME/node-pack"
tar -xJf node-${NODE_VER}-linux-arm64.tar.xz -C "$HOME/node-pack" --strip-components=1
export PATH="$HOME/node-pack/bin:$PATH"
node -v    # 期望 v22.x
npm -v
```

**B3. 下载并打包 OpenClaw（完整 `node_modules`）**

必须在 **真实 aarch64 Linux** 上执行（`uname -m` → `aarch64`）。  
**不要**在 x86/Windows 上用 `--cpu arm64` 交叉装——很多 optional 原生包（`@img/sharp-linux-arm64`、`sqlite-vec` 等）会报「arm64 依赖没有 / 404 / Unsupported platform」。

```bash
uname -m   # 必须是 aarch64；否则换机器或用下方 Docker 方式

WORKDIR="$HOME/openclaw-offline-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" && cd "$WORKDIR"

OPENCLAW_VER=latest
npm init -y

# 走官方 registry，避免国内镜像缺 arm64 optional 包
npm config set registry https://registry.npmjs.org/

# 强制用预编译二进制，避免本机编译 libvips（鲲鹏交叉场景易挂）
export npm_config_platform=linux
export npm_config_arch=arm64
export SHARP_IGNORE_GLOBAL_LIBVIPS=1

npm install "openclaw@${OPENCLAW_VER}" --foreground-scripts

# 确认 CLI
./node_modules/.bin/openclaw --version

# 可选：若日志里 sharp 失败，但对 Cube skill 不需要图片处理，可忽略；
# 若需要图片能力，再显式补装：
# npm install sharp --foreground-scripts

cd ..
tar czf openclaw-bundle-linux-arm64.tar.gz -C "$WORKDIR" .
ls -lh openclaw-bundle-linux-arm64.tar.gz
```

**没有 aarch64 联网机时：用 Docker 模拟 arm64 打包**（宿主机可以是 x86，需 Docker + qemu）：

```bash
NODE_VER=v22.22.3
# 先准备好 node-*-linux-arm64.tar.xz 在当前目录

docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -w /work \
  ubuntu:24.04 bash -lc '
    set -e
    apt-get update && apt-get install -y xz-utils ca-certificates
    tar -xJf node-'"${NODE_VER}"'-linux-arm64.tar.xz -C /usr/local --strip-components=1
    node -v
    rm -rf openclaw-offline-build && mkdir openclaw-offline-build && cd openclaw-offline-build
    npm init -y
    npm config set registry https://registry.npmjs.org/
    export SHARP_IGNORE_GLOBAL_LIBVIPS=1
    npm install openclaw@latest --foreground-scripts
    ./node_modules/.bin/openclaw --version
    cd ..
    tar czf openclaw-bundle-linux-arm64.tar.gz -C openclaw-offline-build .
  '
```

可选：把确切版本写进文件名：

```bash
VER=$(./node_modules/.bin/openclaw --version 2>/dev/null | tr -d '[:space:]' || echo unknown)
mv openclaw-bundle-linux-arm64.tar.gz "openclaw-bundle-linux-arm64-${VER}.tar.gz"
```

**不要**只做 `npm pack openclaw`：那个 tarball **不含依赖**，到鲲鹏后仍要联网 `npm install`。

**B3b. 「arm64 很多依赖没有」时怎么处理**

| 原因 | 表现 | 处理 |
|------|------|------|
| 在 **x86** 上交叉 `npm install` | `Unsupported platform` / optional 跳过 / `@img/sharp-linux-arm64` 404 | 换 **真 aarch64** 或上面的 **Docker `--platform linux/arm64`** |
| 用了淘宝/华为 **npm 镜像** | arm64 optional 包未同步 | `npm config set registry https://registry.npmjs.org/` 后重装 |
| 在 **鲲鹏本机** 直接 `npm install` | 无公网，大量 404 / ETIMEDOUT | 必须离线 bundle，不要在鲲鹏装依赖 |
| 只解压了 Node，又去跑官方 install 脚本 | 脚本继续联网拉包 | Node tar 装好后，只解压已打好的 `openclaw-bundle` |
| `sharp` / `node-gyp` 编译失败 | 缺 gcc、想源码编译 | 设 `SHARP_IGNORE_GLOBAL_LIBVIPS=1`，用预编译；Cube skill **不依赖** sharp，可 `--omit=optional` 先打通 CLI |

仅验证 Cube skill、可暂时跳过可选原生依赖：

```bash
npm install "openclaw@${OPENCLAW_VER}" --omit=optional --foreground-scripts
./node_modules/.bin/openclaw --version
```

**B4. 拷到鲲鹏的文件清单**

```text
~/offline-pkgs/
  cube-python-wheels-py312-aarch64.tar.gz   # 或散开的 quickstart-pkgs/
  install-e2b-offline.sh                    # 可选，与 tar 同目录
  node-v22.*-linux-arm64.tar.xz             # 与打包机相同文件
  openclaw-bundle-linux-arm64.tar.gz        # 或带版本号的文件名
```

> OpenClaw **对话模型**还需能访问的 LLM API（内网 OpenAI 兼容端点 / 厂商内网网关均可）。  
> 装包可完全离线；模型地址填你环境可达的内网 URL。

#### 3.6.2 前置确认（鲲鹏）

```bash
systemctl is-active cube-sandbox-control.target
curl -sS http://127.0.0.1:3000/health
cubemastercli tpl list    # 至少一个 READY 模板

# 本机 DNS（同机必通）
getent hosts 49999-test.cube.app || nslookup 49999-test.cube.app
```

若 DNS 异常，见 §5.1（`CUBE_PROXY_DNSMASQ_MODE=standalone`）。

#### 3.6.3 环境变量（本机）

```bash
export E2B_API_URL="http://127.0.0.1:3000"
export E2B_API_KEY="e2b_000000"
export CUBE_TEMPLATE_ID="<READY 的 template_id>"
export SSL_CERT_FILE="$(mkcert -CAROOT)/rootCA.pem"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
# 常见路径：/root/.local/share/mkcert/rootCA.pem
```

本机 **不需要** `CUBE_PROXY_NODE_IP`。可写入 `~/.bashrc` 持久化。

#### 3.6.4 鲲鹏离线安装 Python 3.12 + e2b

推荐先用 §3.6.1-A0 的 GitHub Release 包（或已拷到 `~/offline-pkgs/` 的同名 tar）。

```bash
cd ~/offline-pkgs
tar xzf cube-python-wheels-py312-aarch64.tar.gz   # 若已是 quickstart-pkgs/ 目录可跳过

# 若你是源码 make altinstall 到 /usr/local/python3.12，先把新版本放进 PATH
export PATH="/usr/local/python3.12/bin:$PATH"
python3.12 -V

# 旧的 3.9 venv 不要复用，直接删掉重建
rm -rf ~/cube-demo/.venv
python3.12 -m venv ~/cube-demo/.venv
source ~/cube-demo/.venv/bin/activate
python -V    # 期望 3.12.x

# 一键安装（脚本会校验 pyqwest aarch64 wheel）
bash install-e2b-offline.sh

# 或手动：wheel 必须匹配 cp312 + aarch64
# pip install --no-index --find-links=./quickstart-pkgs/ \
#   e2b-code-interpreter python-dotenv rich

python -c "import e2b_code_interpreter; print('ok', e2b_code_interpreter.__version__)"
```

若 `python3.12` 找不到，先定位实际安装路径：

```bash
find /usr/local -name 'python3.12' 2>/dev/null
```

然后把对应目录写入 `~/.bashrc`：

```bash
echo 'export PATH="/usr/local/python3.12/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### 3.6.5 第一段演示：`code-sandbox-quickstart`（先做）

先验证 Cube 控制面 / 数据面，再装 OpenClaw。

```bash
source ~/cube-demo/.venv/bin/activate
# 已 export §3.6.3 变量，或写入示例目录 .env

cd /path/to/CubeSandbox/examples/code-sandbox-quickstart
cp .env.example .env
```

编辑 `.env`（本机示例；这里是写文件，不是 export）：

```bash
cat > .env <<'EOF'
E2B_API_URL=http://127.0.0.1:3000
E2B_API_KEY=e2b_000000
CUBE_TEMPLATE_ID=<READY 的 template_id>
SSL_CERT_FILE=/root/.local/share/mkcert/rootCA.pem
REQUESTS_CA_BUNDLE=/root/.local/share/mkcert/rootCA.pem
EOF
```

运行：

```bash
python exec_code.py    # run_code
python cmd.py          # commands.run
```

期望：能创建沙箱并打印执行结果；沙箱架构为 **aarch64**。  
此步失败时先不要装 OpenClaw——问题在 Cube / 模板 / DNS / 证书。

也可先用一行最小脚本自检：

```bash
python3 - <<'PY'
import os
from e2b_code_interpreter import Sandbox

with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"], timeout=600) as sbx:
    print("sandbox_id =", sbx.sandbox_id)
    print(sbx.run_code("import platform; print(platform.machine())"))
    print(sbx.commands.run("uname -a").stdout)
PY
```

WebUI（可选）：`http://127.0.0.1:12088`

#### 3.6.6 鲲鹏离线安装 Node.js + OpenClaw（前台常驻）

`code-sandbox-quickstart` 通过后再装 OpenClaw（使用 §3.6.1-B 打好的包）。

```bash
cd ~/offline-pkgs

# 1) 安装 Node（系统级；也可用 ~/node 用户目录）
sudo tar -xJf node-v22.*-linux-arm64.tar.xz -C /usr/local --strip-components=1
hash -r
node -v    # v22.x
npm -v

# 2) 解压 OpenClaw 离线 bundle（从未在鲲鹏上 npm install）
mkdir -p ~/openclaw-app
tar xzf openclaw-bundle-linux-arm64*.tar.gz -C ~/openclaw-app

# 3) 把 CLI 放进 PATH（路径按实际解压目录改；示例为 ~/openclaw-app）
OPENCLAW_BIN="$HOME/openclaw-app/node_modules/.bin"
# 若 bundle 解在其它目录，例如：
# OPENCLAW_BIN="/home/<用户>/02-cubesandbox/node/node_modules/.bin"

grep -q 'openclaw-app/node_modules/.bin' ~/.bashrc || \
  echo "export PATH=\"${OPENCLAW_BIN}:\$PATH\"" >> ~/.bashrc
source ~/.bashrc

which openclaw
openclaw --version
```

> **不要用 `npx openclaw`**（离线 bundle 场景）：`npx` 可能走到别的版本，且 exec 子进程环境更不可控。  
> 若 `openclaw: command not found`，用 **`${OPENCLAW_BIN}/openclaw`** 全路径，或按上一步写入 `~/.bashrc`。

首次配置（模型 API 填**内网可达**地址；只跑初始化，不装 daemon）：

```bash
openclaw onboard
# 排障：openclaw doctor
openclaw doctor
```

> 不要在鲲鹏 root + SSH 环境里使用 `openclaw onboard --install-daemon` 或
> `openclaw gateway install`：常会因为 `systemctl --user` / D-Bus 不可用而失败。

##### 必做：`openclaw.json`（让 Agent 的 exec 找到 e2b SDK）

**现象**：你在 shell 里 `python3 -c "import e2b_code_interpreter"` 能成功，但 Dashboard 里 Agent 报 `ModuleNotFoundError`。  
**原因**：OpenClaw 的 **exec 工具**在宿主机上默认只用精简 `PATH`（`/usr/local/bin:/usr/bin:/bin`），**不会**继承你启动 Gateway 时的 venv；裸写 `python3` 会落到系统 3.9。

在 `~/.openclaw/openclaw.json` 写入（路径按本机改；e2b 装在 **`/root/cube-demo/.venv`** 时示例如下）：

```bash
mkdir -p ~/.openclaw

cat > ~/.openclaw/openclaw.json <<'EOF'
{
  "tools": {
    "exec": {
      "pathPrepend": [
        "/root/cube-demo/.venv/bin",
        "/usr/local/python3.12/bin"
      ]
    }
  },
  "env": {
    "CUBE_TEMPLATE_ID": "<READY 的 template_id>",
    "E2B_API_URL": "http://127.0.0.1:3000",
    "E2B_API_KEY": "e2b_000000",
    "SSL_CERT_FILE": "/root/.local/share/mkcert/rootCA.pem",
    "REQUESTS_CA_BUNDLE": "/root/.local/share/mkcert/rootCA.pem"
  }
}
EOF
```

若 OpenClaw 解在自定义目录，可在 `pathPrepend` 末尾再加一项，例如  
`/home/<用户>/02-cubesandbox/node/node_modules/.bin`（仅影响 `openclaw` CLI，**e2b 仍须 venv 路径在前**）。

改完 **必须重启 Gateway**。验证：Dashboard 里让 Agent 只跑一行：

```text
/root/cube-demo/.venv/bin/python3 -c "import sys,e2b_code_interpreter; print(sys.executable); print('ok')"
```

期望输出含 `/root/cube-demo/.venv/bin/python3` 和 `ok`。

> Gateway 以非 root 用户运行时，须能读 `/root/cube-demo/.venv`；否则把 venv 拷到该用户目录并改 `pathPrepend`。

##### 可选：`~/.openclaw/cube.env`（给人看 / 启动脚本用）

`cube.env` **不在** skill 目录；Agent **不应**去 `skills/cube-sandbox/cube.env` 找配置（应在 `openclaw.json`）。

```bash
cat > ~/.openclaw/cube.env <<'EOF'
export PATH="/root/cube-demo/.venv/bin:/usr/local/python3.12/bin:$PATH"
E2B_API_URL=http://127.0.0.1:3000
E2B_API_KEY=e2b_000000
CUBE_TEMPLATE_ID=<READY 的 template_id>
SSL_CERT_FILE=/root/.local/share/mkcert/rootCA.pem
REQUESTS_CA_BUNDLE=/root/.local/share/mkcert/rootCA.pem
EOF
```

**启动 Gateway**（`openclaw.json` 已配置后，exec 环境以 json 为准；下面 `source cube.env` 主要方便本机自检）：

```bash
export PATH="${OPENCLAW_BIN:-$HOME/openclaw-app/node_modules/.bin}:$PATH"
set -a && source ~/.openclaw/cube.env && set +a

/root/cube-demo/.venv/bin/python3 -c "import e2b_code_interpreter; print('ok')"
openclaw gateway --bind loopback --port 18789
```

<details>
<summary>不想每次手动 source 的替代做法</summary>

**A. 写进 `~/.bashrc`（登录 SSH 后自动加载）**

```bash
grep -q 'cube.env' ~/.bashrc || cat >> ~/.bashrc <<'EOF'

# CubeSandbox skill 环境变量
if [ -f ~/.openclaw/cube.env ]; then
  set -a && . ~/.openclaw/cube.env && set +a
fi
EOF
source ~/.bashrc
# 之后可直接：openclaw gateway --bind loopback --port 18789
```

**B. 启动脚本（一条命令）**

```bash
mkdir -p ~/bin
cat > ~/bin/openclaw-gateway-cube <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
set -a && source ~/.openclaw/cube.env && set +a
exec openclaw gateway --bind loopback --port 18789 "$@"
EOF
chmod +x ~/bin/openclaw-gateway-cube
grep -q '$HOME/bin' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
# 之后：openclaw-gateway-cube
```

</details>

前台常驻：上述命令占用的 SSH 窗口**不要关**；要停 Gateway 用 Ctrl+C。

从你的电脑访问 Dashboard 的推荐方式：

```bash
# 在你的电脑上执行
ssh -N -L 18789:127.0.0.1:18789 root@<鲲鹏IP>
```

然后浏览器打开：

```text
http://127.0.0.1:18789/
```

若提示 `device signature expired`，通常是**客户端与鲲鹏时间差超过 10 分钟**
或浏览器残留了旧设备签名。先同步时间，再清浏览器站点数据，并执行：

```bash
openclaw devices list
openclaw devices clear --yes --pending
```

#### 3.6.7 第二段演示：`openclaw-integration`

##### 安装 skill（UTF-8，勿乱码）

从仓库 **整目录复制**（避免 Windows/错误编码导致 SKILL 乱码，模型无法识别 skill）：

```bash
rm -rf ~/.openclaw/workspace/skills/cube-sandbox
cp -r /path/to/CubeSandbox/examples/openclaw-integration/skills/cube-sandbox \
  ~/.openclaw/workspace/skills/

file ~/.openclaw/workspace/skills/cube-sandbox/SKILL.md
head -3 ~/.openclaw/workspace/skills/cube-sandbox/SKILL.md
# 应看到正常中文「Cube Sandbox 安全沙箱执行技能」，而不是「瀹夊叏娌欑…」
```

若已乱码：在 PC 上用 UTF-8 重新 scp `SKILL.md`，或从 git 仓库重新 `cp`。

拷完 skill 后 **Ctrl+C 停 Gateway 再启动**（见 §3.6.6 启动命令）。

##### 联调要点（已验证）

| 项 | 做法 |
|----|------|
| e2b SDK | 装在 **`/root/cube-demo/.venv`**（§3.6.4），与 quickstart 同一 venv |
| Agent 用 Python | **`openclaw.json` → `tools.exec.pathPrepend`** 含 venv/bin（§3.6.6 必做） |
| Cube 变量 | **`openclaw.json` → `env`**，不要只在 skill 目录放 `cube.env` |
| OpenClaw CLI | 离线 bundle 的 `node_modules/.bin/openclaw` 写入 PATH；**不用 npx** |
| 创建沙箱超时 | §5.2：重启 cubelet + network-agent，清卡死 shim |
| Agent 乱探路 | 约束话术 + skill 内「禁止 pip/curl/hosts/nginx」；见下表 |

##### Dashboard 话术（可直接复制）

| 场景 | 示例话术 |
|------|----------|
| Python（验证 quickstart） | 请在 Cube 沙箱里跑一段 Python，计算 1 到 100 的和，把结果和 `platform.machine()` 一起返回。**不要 pip install** |
| Shell | 用沙箱执行 `uname -a`，把完整输出返回给我 |
| 架构确认 | 在隔离沙箱中运行 Python：`import platform; print(platform.machine())` |
| 断网 | 在完全断网的沙箱里运行 Python，尝试访问外网并说明是否被阻断 |
| 读文件 | 在沙箱里读取 `/etc/hosts` 的内容并展示 |

期望：一次或少量 exec 即可完成；输出含 **5050**、**aarch64**。若出现 20+ 次 curl/docker/nginx 探路 → 检查 `openclaw.json` 的 `pathPrepend` 与 SKILL 编码。

更细的 skill 说明见 [`examples/openclaw-integration/README_zh.md`](examples/openclaw-integration/README_zh.md)。

#### 3.6.8 OpenClaw + 沙箱适用场景（鲲鹏本机）

以下场景均适合在 **鲲鹏同机** OpenClaw + Cube 上跑（DNS / API 已通、模型走内网 LLM）：

| 场景 | 你可以让 Agent 做什么 | 价值 |
|------|----------------------|------|
| **不可信代码试跑** | 「在沙箱里运行用户提交的 Python，只返回 stdout，不要改宿主机」 | 隔离恶意或误操作代码 |
| **数据分析片段** | 「在沙箱用 pandas 读我描述的 CSV 逻辑并汇总统计」（需模板内或有 pip 离线包） | 分析逻辑在 VM 内执行 |
| **Shell 探针** | 「在沙箱执行 `uname -a`、`free -h`、检查 aarch64」 | 验证环境与架构 |
| **断网合规** | 「在完全断网沙箱运行这段访问内网的脚本，确认无法出网」 | 演示网络策略 |
| **一次性构建/脚本** | 「在沙箱里编译并运行 hello world，完成后销毁」 | 不污染宿主机 |
| **Skill 编排入口** | 自然语言 → OpenClaw 调 cube-sandbox skill → `Sandbox.create` → 返回结果 | 给非开发人员用的对话式沙箱 |
| **与 quickstart 对齐的回归** | 固定话术跑 `exec_code` / `cmd.py` 同等逻辑 | 发版后冒烟 |

**不太适合仅靠对话完成的**：大规模并发压测（用 `cube-bench` / 脚本）、改 Cube 集群配置、离线装 npm/pip 包（须事先在 venv/bundle 准备好）。

#### 3.6.9 离线装包与 OpenClaw 排错

| 现象 | 处理 |
|------|------|
| `pip` 报 `No matching distribution` / 只有 `x86_64` wheel | 下载机架构不对；用 aarch64 重下，或加 `--platform ..._aarch64` |
| `No matching distribution found for pyqwest` | `e2b` 的传递依赖；离线包缺 **aarch64** 版 `pyqwest` / `protobuf-py-ext`。直接用 §3.6.1-A0 [预打包 Release](https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64)，或按 A1/A2 整包重下，不要只拷 top3 wheel |
| 想在鲲鹏直接 `npm install -g openclaw` | 无公网会失败；必须用 §3.6.1-B 的 bundle |
| `openclaw: command not found` | `PATH` 未含 OpenClaw 的 `node_modules/.bin`；见 §3.6.6，或用全路径启动 |
| Dashboard 报 `No module named 'e2b_code_interpreter'` | shell 里 import 成功但 Agent 失败 → **未配置** `openclaw.json` 的 `tools.exec.pathPrepend`（§3.6.6） |
| Agent 要去 `skills/.../cube.env` 或 `pip install` | 环境应在 `openclaw.json`；鲲鹏无公网禁止在线 pip |
| SKILL.md 乱码（`瀹夊叏…`） | 重新 UTF-8 复制 skill；§3.6.7 |
| Agent 大量 curl/docker/nginx 探路 | 约束话术 + 确认 `pathPrepend`；正常应 1～2 次 Python exec |
| Skill 未创建沙箱 / `Template not found` | 检查 `openclaw.json` 的 `env.CUBE_TEMPLATE_ID` |
| 打包时提示 arm64 依赖没有 / `Unsupported platform` / sharp 404 | 见 §3.6.1-B3b：不要在 x86 交叉装；改用真 aarch64 或 Docker `linux/arm64`；registry 用 npmjs.org |
| `npm` / `openclaw` 报 `sharp` / ELF 错误 | bundle 架构不对或缺预编译包；aarch64 重打，或 `--omit=optional` 先跑通 Cube skill |
| `npm pack openclaw` 拷过来仍缺模块 | 预期：`npm pack` 不含依赖；改用完整 `node_modules` tar |
| quickstart `run_code` DNS 失败 | 本机 DNS：§5.1；确认未改坏 `/etc/resolv.conf` |
| Skill 触发但 SSL 失败 | `SSL_CERT_FILE` 写入 `openclaw.json` 的 `env` |
| OpenClaw 能起、对话超时 | 模型 API 外网不通；改配内网 endpoint |
| 华为 PyPI 镜像缺 `e2b-code-interpreter` | 预期；走 §3.6.1-A 离线 wheel |
| `Sandbox.create` / WebUI 创建报 `ttrpc ... Receive packet timeout` | 运行时 shim 卡死；§5.2 重启 cubelet + network-agent |

---

## 4. 防火墙（仅当其他机器要访问 API 时）

单机部署、**仅在本机跑 SDK** 时通常不必改 firewalld。  
若另一台机器需要调用 CubeAPI / WebUI，再放行以下端口。

### 4.1 需要放行的端口

| 端口 | 协议 | 是否建议对外开放 | 用途 |
|------|------|------------------|------|
| 3000 | TCP | **是**（远端 API） | CubeAPI / `E2B_API_URL` |
| 80 | TCP | **是** | CubeProxy HTTP |
| 443 | TCP | **是** | CubeProxy HTTPS（`*.cube.app`） |
| 12088 | TCP | 可选 | WebUI 控制台 |
| ICMP | — | 可选 | ping 排查连通性 |
| 3306 / 6379 | TCP | **否** | MySQL / Redis，仅本机 |
| 8089 / 9999 | TCP | **否**（单机） | CubeMaster / Cubelet，多机集群才需要 |

### 4.2 firewalld 一键放行（对所有来源）

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=12088/tcp
sudo firewall-cmd --permanent --add-protocol=icmp
sudo firewall-cmd --reload

sudo firewall-cmd --list-ports
sudo firewall-cmd --list-protocols
```

### 4.3 仅允许指定客户端 IP（更安全）

把 `10.0.0.20` 换成另一台机器的 IP：

```bash
CLIENT_IP=10.0.0.20

sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${CLIENT_IP}\" port port=\"3000\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${CLIENT_IP}\" port port=\"80\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${CLIENT_IP}\" port port=\"443\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${CLIENT_IP}\" port port=\"12088\" protocol=\"tcp\" accept"
sudo firewall-cmd --reload
sudo firewall-cmd --list-rich-rules
```

### 4.4 远端自检（可选）

```bash
curl -sS "http://<鲲鹏IP>:3000/health"
curl -kI "https://<鲲鹏IP>/"
curl -sS -o /dev/null -w "%{http_code}\n" "http://<鲲鹏IP>:12088/"
```

> 若系统没有 firewalld，可用 `iptables` / `ufw` 放行同样端口；云厂商安全组也需同步放行。

---

## 5. 常见问题速查

| 现象 | 处理 |
|------|------|
| `assets/package/sandbox-package.tar.gz not found` | 必须用完整 one-click arm64 发布包，不要用 git 源码目录直接装 |
| `client.timeout exceeded while awaiting headers` | TCR 不通；用离线镜像包 `load-images.sh` |
| `platform linux/amd64 does not match host` | 删掉错误镜像，重新 load **arm64** 包（勿用旧包） |
| `systemctl restart` 一直卡住 | 多半在 `docker pull`；先 stop，确保本地有镜像，再 start |
| 仍拉 `cube-sandbox-int...` | `.one-click.env` 设置 `MIRROR=cn`，并保证 cn 名本地已有 arm64 镜像（load 脚本会 tag） |
| `/data/cubelet` not XFS | 挂 XFS 盘或做 loopback XFS 再装 |
| `cube-sandbox-dns.service not ready` / `dnsmasq did not bind 169.254.254.53:53` | NetworkManager 的 dnsmasq 插件未监听；改用独立 dnsmasq（见下） |
| `failed to resolve image` / `tencentcloudcr.com:443: i/o timeout` | 远程仓库不可达；离线请走 §2.0～2.3 |
| `native export failed to resolve ... index.docker.io ... i/o timeout` | **不是平台不匹配**。默认 native 导出把短名当成 Docker Hub。设 `CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false` 并重启 cubemaster（§2.0） |
| `requested image's platform (linux/amd64) does not match` | 才是平台问题；删掉 amd64 镜像，重新 load arm64 离线包 |
| Android 模板 `sandbox-android-redroid` 平台不对 | 用 §2.4.1 的 Android 离线包 `docker load`，确认 `Architecture=arm64`；勿混用 §1.3 的 one-click 组件包 |
| `mirrors.tools.huawei.com/pypi/simple` 找不到 `e2b-code-interpreter` | 该内网镜像未同步此包；按 §3.6.1-A0 下载 [预打包 Release](https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64)，或在联网机 `pip download` 后在鲲鹏 `pip install --no-index --find-links=...` |
| `getaddrinfo failed` / `49999-*.cube.app` 解析失败 | 客户端不在集群 DNS 域内；**在鲲鹏本机跑 SDK / OpenClaw**（§3.6），不要从 Windows 远程当执行端 |
| `install.sh` 长时间无输出 | 多半在等 systemd；另开终端看 `systemctl list-jobs`。若已 `install complete`，不要反复全量安装，直接做模板 |
| 创建沙箱报 `ttrpc ... Receive packet timeout` / WebUI（12088）与 Python 同错 | 多为卡死 shim 或 network-agent 状态异常；见 §5.2 快速修复 |

### 5.1 DNS / dnsmasq 修复（单机常见）

```bash
command -v dnsmasq || sudo yum install -y dnsmasq || sudo dnf install -y dnsmasq

ENV=/usr/local/services/cubetoolbox/.one-click.env
grep -q '^CUBE_PROXY_DNSMASQ_MODE=' "$ENV" \
  && sudo sed -i 's/^CUBE_PROXY_DNSMASQ_MODE=.*/CUBE_PROXY_DNSMASQ_MODE=standalone/' "$ENV" \
  || echo 'CUBE_PROXY_DNSMASQ_MODE=standalone' | sudo tee -a "$ENV"

# 避免系统自带 dnsmasq 抢 53 端口
sudo systemctl disable --now dnsmasq.service 2>/dev/null || true

sudo systemctl restart cube-sandbox-coredns.service
sudo systemctl restart cube-sandbox-dns.service
ss -ulnp | grep 169.254.254.53
sudo /usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh
```

查看进展：

```bash
systemctl list-jobs
systemctl status cube-sandbox-control.target --no-pager -l
journalctl -u cube-sandbox-dns.service -n 80 --no-pager
journalctl -u 'cube-sandbox-*' -n 100 --no-pager
```

### 5.2 创建沙箱 ttrpc 超时 / 卡死 shim（运行时常见）

**现象（WebUI `http://<节点IP>:12088/sandboxes` 与 Python `Sandbox.create()` 相同）：**

```text
Create sandbox failed: ... ttrpc err: Receive packet timeout
failed to run container ... failed to create shim task ...
```

CubeShim 日志里可能还有 `not found container`、`Broken pipe` 等清理失败——这些是连带报错，可忽略。

**含义：** Cubelet → CubeShim → MicroVM 里的 cube-agent 在 `CreateSandbox` 阶段超时（默认约 25s）。  
**不是** Python SDK / e2b 包问题；12088 页面与脚本走同一条 API 链路。

**若之前能创建、突然全部失败：** 优先怀疑 **残留 shim / network-agent 状态异常**，不必先改沙箱网段。  
**若从未成功过：** 再查 §2.0 模板、XFS、内存，以及 [沙箱网段与内网冲突](docs/zh/guide/troubleshooting/local-network-cidr-conflict.md)。

#### 快速修复（多数情况有效）

```bash
# 1. 看有没有卡死的 shim
ps aux | grep containerd-shim-cube-rs | grep -v grep

# 2. 重启计算面 + 网络（会清掉残留 shim）
sudo systemctl restart cube-sandbox-cubelet.service
sudo systemctl restart cube-sandbox-network-agent.service
sleep 5

# 3. 确认 shim 已清空
ps aux | grep containerd-shim-cube-rs | grep -v grep   # 应为空

# 4. 再在 WebUI 或 quickstart 里创建一次
curl -sS http://127.0.0.1:3000/health
curl -sS http://127.0.0.1:19090/health 2>/dev/null || echo "network-agent health fail"
```

#### 仍失败时再查

```bash
df -hT /data/cubelet /data/log
free -h
cubemastercli tpl list    # 至少一个 READY

# 复现一次 create 的同时看 Shim 日志
grep -a -E 'start vm|vm ready|agent is ready|Create sandbox|timeout' \
  /data/log/CubeShim/cube-shim-req.log | tail -30
```

| 日志特征 | 可能原因 |
|----------|----------|
| 无 `vm ready` | hypervisor / guest 内核未起来 → 查 `/data/log/CubeVmm/vmm.log` |
| 有 `agent is ready` 后 timeout | guest 内网络或存储挂载卡住 → 查 network-agent、磁盘 |
| 重启 cubelet 后恢复 | 确认为 shim 泄漏；若频繁复发，查内存与 `/data/cubelet` 空间 |

---

## 6. 建议操作清单（当前进度）

- [x] 下载 one-click arm64 包并解压  
- [x] 下载并解压离线 Docker arm64 镜像包 / `load-images.sh`  
- [x] `.env` / `.one-click.env`：`MIRROR=cn`；必要时 `CUBE_PROXY_DNSMASQ_MODE=standalone`  
- [x] `install.sh` → **`install complete`**  
- [ ] **`CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false` + 重启 cubemaster**（§2.0；两边 env 都写）  
- [ ] `docker tag ... sandbox-code:latest`，确认 `Architecture=arm64`  
- [ ] `tpl create-from-image --image sandbox-code:latest` → `READY`，记下 `template_id`  
- [ ] （可选 **Android 预览**）§2.4.1 下载 [Android 离线包](https://github.com/LOLHenry/CubeSandbox/releases/tag/android-kunpeng-arm64-preview) → `docker load` → 确认 `sandbox-android-redroid` 为 arm64  
- [ ] （可选 **Android 预览**）§2.4.3 `tpl create-from-image --image sandbox-android-redroid:16.0.0-arm64`（需运行时支持）  
- [ ] **离线 Python**：§3.6.1-A0 下载 [预打包 Release](https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64) → §3.6.4 装到鲲鹏  
- [ ] **第一段演示**：§3.6.5 `code-sandbox-quickstart`（`exec_code.py` / `cmd.py`）通过  
- [ ] **OpenClaw 配置**：§3.6.6 `openclaw.json`（`pathPrepend` + `env`）+ skill UTF-8 安装  
- [ ] **第二段演示**：§3.6.7 Dashboard 话术触发 cube-sandbox（5050 / aarch64）  
- [ ] （可选）§3.6.8 场景扩展（断网 / 不可信代码试跑等）  
- [ ] （可选）firewalld 放行 3000/80/443，供其他机器只访问 API/WebUI  

**当前下一步：§3.6.7 OpenClaw Dashboard 联调 → §3.6.8 按业务选场景试用。**

---

## 7. 相关链接

| 说明 | 链接 |
|------|------|
| 官方 OpenClaw 集成 | [examples/openclaw-integration/README_zh.md](examples/openclaw-integration/README_zh.md) |
| 代码沙箱快速入门 | [examples/code-sandbox-quickstart/README_zh.md](examples/code-sandbox-quickstart/README_zh.md) |
| 官方裸金属部署 | [docs/zh/guide/bare-metal-deploy.md](docs/zh/guide/bare-metal-deploy.md) |
| 官方 ARM 支持说明 | [docs/zh/blog/posts/2026-07-08-cubesandbox-arm-support.md](docs/zh/blog/posts/2026-07-08-cubesandbox-arm-support.md) |
| one-click arm64 包 | GitHub / CNB Releases 中的 `cube-sandbox-one-click-*-arm64.tar.gz` |
| 离线 Docker arm64 包 | https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-docker-arm64-v0.6.0 |
| Android 沙箱离线包（ReDroid AOSP 16 / preview） | https://github.com/LOLHenry/CubeSandbox/releases/tag/android-kunpeng-arm64-preview |
| Android 沙箱离线包（ReDroid + envd / preview） | https://github.com/LOLHenry/CubeSandbox/releases/tag/android-kunpeng-arm64-envd-preview |
| e2b 离线 Python wheels（aarch64 / cp312） | https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64 |
