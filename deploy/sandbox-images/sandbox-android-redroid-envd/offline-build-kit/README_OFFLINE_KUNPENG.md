# 鲲鹏离线编译 envd + 打 ReDroid+envd 镜像

本离线包在**有网环境**打好，拷到鲲鹏（euler）后**无需访问 GitHub / Docker Hub / proxy.golang.org**。

## 包内容

| 路径 | 说明 |
|------|------|
| `go/go1.25.4.linux-arm64.tar.gz` | Go 工具链（鲲鹏原生 arm64） |
| `src/infra/` | `e2b-dev/infra@2026.16` + `go mod vendor` |
| `src/envd-starter/` | ReDroid PID1 启动器源码 |
| `src/android-init/` | init.rc 等 |
| `images/redroid-*-docker.tar.gz` | ReDroid 基础镜像（可选，已包含时） |
| `images/golang-*-docker.tar.gz` | golang 构建镜像（可选） |
| `scripts/01-04-*.sh` | 鲲鹏上一键步骤 |
| `Dockerfile.offline` | 离线 Docker 构建 |
| `MANIFEST.json` | 版本清单 |

## 鲲鹏操作步骤

```bash
# 0. 解压
tar xzf android-envd-offline-build-kit.tar.gz
cd android-envd-offline-build-kit
cat MANIFEST.json

# 1. 安装 Go（仅需一次）
./scripts/01-install-go.sh
export PATH=/usr/local/go/bin:$PATH

# 2a. 只编译 envd 二进制（不依赖 Docker 构建镜像）
./scripts/02-build-binaries.sh
ls -lh out/envd out/envd-starter

# 2b. 打完整 Docker 镜像（需 docker + 已 load ReDroid）
#     若包内带 images/redroid-*.tar.gz 会自动 load
./scripts/03-build-docker-image.sh

# 3. 校验镜像
./scripts/04-verify.sh
# 可选冒烟（privileged docker run）：
RUN_SMOKE=1 ./scripts/04-verify.sh
```

## 产出镜像

- `sandbox-android-redroid-envd:16.0.0-arm64`
- 用于 `cubemastercli tpl create-from-image --image sandbox-android-redroid-envd:16.0.0-arm64 ...`

## 常见问题

**Q: `go mod vendor` 为什么在鲲鹏上不用再跑？**  
A: 有网机器打包时已 vendor，鲲鹏上 `GOPROXY=off` 直接 `go build -mod=vendor`。

**Q: 没有 golang Docker 镜像怎么办？**  
A: `03-build-docker-image.sh` 会自动走「先 `02-build-binaries.sh` 再 inject 进 ReDroid」路径。

**Q: envd 必须是 Android ELF？**  
A: 是。`file out/envd` 应含 `interpreter /system/bin/linker64`，不能是 `statically linked`（那是 GOOS=linux）。

## 版本

见 `MANIFEST.json`：`envd_ref`、`infra_commit`、`go_version`。
