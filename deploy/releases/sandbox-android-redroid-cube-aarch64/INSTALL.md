# sandbox-android-redroid-cube (aarch64) — Kunpeng 离线 Release

ReDroid AOSP 16 + **fd-sanitize-starter** OCI ENTRYPOINT：在 `exec /init` 前清理 cube-agent/shim 继承的 FIFO fd，**无需修改 cube-agent / shim**。

## Release 内容

| 文件 | 说明 |
|------|------|
| `bin/fd-sanitize-starter` | aarch64 静态二进制（已预编译） |
| `Dockerfile.inject` | 离线注入 ReDroid base |
| `build-docker-image.sh` | 在鲲鹏上构建 Docker 镜像 |
| `build-offline-docker-bundle.sh` | 导出 `docker save` 离线包 |
| `examples/redroid-cold-fd-sanitize.json` | cubemastercli 冷启动 JSON |
| `BUILDINFO` | 构建元数据 |

## 前置条件（鲲鹏 euler-arm）

- Docker arm64，`redroid:16.0.0_64only-latest` 或 `sandbox-android-redroid:16.0.0-arm64` 已 load
- CubeSandbox v0.6 arm64 one-click 已安装
- `/data/cubelet` 为 XFS

## 方式 A：离线 inject 构建镜像（推荐）

```bash
tar xzf sandbox-android-redroid-cube-aarch64-*.tar.gz
cd sandbox-android-redroid-cube-aarch64-*

# 确保 ReDroid base 存在
docker image inspect redroid:16.0.0_64only-latest --format '{{.Architecture}}'
# 或: sandbox-android-redroid:16.0.0-arm64

chmod +x build-docker-image.sh build-offline-docker-bundle.sh prepare-cubelet-ext4.sh
./build-docker-image.sh
```

成功 tag：

```text
sandbox-android-redroid-cube:16.0.0-arm64
```

### 必做：注册 Cubelet ext4 根文件系统（multirun 前）

`multirun` 示例 JSON 使用 `storage_media: ext4`。**仅 `docker build` 不够** — Cubelet 需要本机已有 ext4/pmem 文件：

```text
/usr/local/services/cubetoolbox/cubebox_os_image/cubebox/sandbox-android-redroid-cube:16.0.0-arm64/...ext4
```

若未注册，会报错：

```text
pmem file ...ext4 not exist and download failed: image spec annotations are empty
```

在 **已 load/build Docker 镜像** 的节点执行（离线环境需 `CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false`，见 README_KUNPENG §2.0）：

```bash
./prepare-cubelet-ext4.sh
# 等价于 cubemastercli tpl create-from-image --image ... --cpu 4000 --memory 6144（无 envd probe）
# 等待 distribution READY 后再 multirun
```

检查 ext4 是否就绪（路径是 **artifact_id**，不是 Docker tag）：

```bash
# 你的 job 输出: artifact_id=rfs-cbaa3e6bb0fdfe4e91e06fe8
ART=rfs-cbaa3e6bb0fdfe4e91e06fe8
ls -lh /usr/local/services/cubetoolbox/cubebox_os_image/${ART}/${ART}.ext4

# 或列出全部
find /usr/local/services/cubetoolbox/cubebox_os_image -name '*.ext4'
```

**multirun 必须使用 artifact id**（`rfs-...`），不能写 Docker 镜像名：

```bash
# 快速改 JSON（把 artifact id 换成你的）
ART=rfs-cbaa3e6bb0fdfe4e91e06fe8
sed "s|sandbox-android-redroid-cube:16.0.0-arm64|${ART}|" \
  examples/redroid-cold-fd-sanitize.json > /tmp/redroid-cold.json

cubemastercli multirun --norm /tmp/redroid-cold.json
```

或使用脚本（新版 release 含 `generate-cold-multirun-json.sh`）：

```bash
./generate-cold-multirun-json.sh rfs-cbaa3e6bb0fdfe4e91e06fe8
cubemastercli multirun --norm examples/redroid-cold-fd-sanitize-rfs-cbaa3e6bb0fdfe4e91e06fe8.json
```

导出离线 docker 包（可选，拷到其他节点）：

```bash
./build-offline-docker-bundle.sh
# 生成 dist/sandbox-android-redroid-cube-docker-*.tar.gz
```

在目标节点：

```bash
gunzip -c sandbox-android-redroid-cube-docker-*.tar.gz | docker load
docker image inspect sandbox-android-redroid-cube:16.0.0-arm64 \
  --format 'entrypoint={{json .Config.Entrypoint}} arch={{.Architecture}}'
```

## 方式 B：仓库内完整 build（需网络拉 golang）

```bash
git clone ... && cd CubeSandbox
./deploy/sandbox-images/sandbox-android-redroid-cube/build.sh
```

## 冷启动验证（不用 tpl）

```bash
cubemastercli destroy <old-sandbox>   # 如有
cubemastercli multirun --norm examples/redroid-cold-fd-sanitize.json
cube-runtime login <sandbox-id>
cat /data/local/tmp/fd-sanitize-starter.log
```

## 验证 Android

```bash
APID=$(for p in /proc/[0-9]*; do tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q second_stage && echo "${p#/proc/}" && break; done)
nsenter -t $APID -m -p -u -i -- getprop init.svc.zygote      # running
nsenter -t $APID -m -p -u -i -- getprop sys.boot_completed  # 1
dmesg | grep -i 'Unsupported_st_mode' | tail -3              # 无新行
```

## 与 envd 版关系

本 release **不含 envd**，专用于验证 FIFO/zygote。通过后可将 `bin/fd-sanitize-starter` 合入 `sandbox-android-redroid-envd` 镜像链。

## GitHub Release

Tag：`sandbox-android-redroid-cube-aarch64`  
Assets：`sandbox-android-redroid-cube-aarch64-<git-short>.tar.gz` 及 `.sha256`
