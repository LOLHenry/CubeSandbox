# Android ReDroid + envd：全自动 ARM64 E2E（鲲鹏 / KVM）

手工在 euler 上 `docker load` → `tpl create-from-image` → 等失败 → 翻日志，迭代效率很低。

**可行方案：** 在已安装 CubeSandbox 的鲲鹏机上注册 **GitHub Actions self-hosted runner**，由 CI 自动完成：

1. `ubuntu-24.04-arm` 构建镜像并上传离线包  
2. **self-hosted runner（euler）** 加载镜像 → 调 API 建模板 → 等到 `READY` 或自动收集诊断日志  

Cloud Agent **不能 SSH 进你的 euler**；self-hosted runner 是「Agent/CI 连上你机器」的标准做法。

---

## 环境要求（runner 所在机 = euler-arm-199）

| 项 | 要求 |
|----|------|
| CPU | aarch64，`/dev/kvm` 存在 |
| CubeSandbox | one-click v0.6 arm64 已安装且 cubemaster/cubelet 在跑 |
| Docker | arm64，可 `docker load` |
| 磁盘 | `/data/cubelet` 在 XFS；`/data/log` 可写 |
| 网络 | runner 能访问 `https://github.com`；本机 `127.0.0.1:8089` cubemaster |

---

## 一次性：注册 self-hosted runner

在 GitHub 仓库：**Settings → Actions → Runners → New self-hosted runner → Linux → ARM64**

在 **euler-arm-199** 上（示例路径）：

```bash
sudo mkdir -p /opt/gh-runner && cd /opt/gh-runner

# 按 GitHub 页面提示下载 arm64 runner 包并解压，然后：
./config.sh \
  --url https://github.com/LOLHenry/CubeSandbox \
  --token <REGISTRATION_TOKEN> \
  --labels linux,arm64,kvm,cubesandbox,self-hosted \
  --name euler-arm-199

sudo ./svc.sh install
sudo ./svc.sh start
```

确认 runner 在 GitHub 上显示 **Idle**，且带标签 `kvm` `cubesandbox`。

---

## 触发全自动 E2E

### 方式 A：打 tag（构建 + E2E）

```bash
git tag android-kunpeng-envd-envd-preview13
git push origin android-kunpeng-envd-envd-preview13
```

Workflow **Android Sandbox Envd E2E** 会：

1. 在 `ubuntu-24.04-arm` 构建离线包  
2. 在 self-hosted runner 下载包 → `e2e-template-ready.sh` → 必须 `READY` 才绿  

### 方式 B：手动 dispatch

Actions → **Android Sandbox Envd E2E** → Run workflow

### 方式 C：仅在 euler 本机跑（不经过 GitHub）

```bash
cd /path/to/CubeSandbox
BUILD_IMAGE=1 ./deploy/sandbox-images/sandbox-android-redroid-envd/e2e-template-ready.sh
```

或测 Release 包：

```bash
BUNDLE_TAR=/path/to/cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview12.tar.gz \
  ./deploy/sandbox-images/sandbox-android-redroid-envd/e2e-template-ready.sh
```

失败时诊断目录默认在 `/tmp/android-envd-e2e-<pid>/`（含 Cubelet/Shim/template stderr 副本）。

---

## 与 GitHub 仅构建的区别

| 环境 | 能做什么 |
|------|----------|
| `ubuntu-24.04-arm`（GitHub 托管） | 构建 arm64 Docker 镜像、打离线包；**不能**跑 CubeVM 模板探活 |
| euler self-hosted + KVM | **完整** `tpl create-from-image` → `READY` 验证 |

`verify-envd-health.sh` 用宿主机 `docker run` 只能粗测，**不能替代** CubeVM 模板路径。

---

## 当前镜像要点（preview12+）

- `ENTRYPOINT`: `/usr/bin/envd-starter`  
- envd: `-isnotfc -no-cgroups -verbose -port 49983`  
- 模板探活: HTTP API `timeout_ms: 120000`（v0.6 CLI 无 `--probe-timeout-ms` 时用 API）

---

## 故障排查

E2E 失败时查看 workflow 上传的 artifact `android-envd-e2e-diagnostics-*`，或 euler 上：

```bash
ls -la /tmp/android-envd-e2e-*/
cat /tmp/android-envd-e2e-*/cubelet-req-tail.txt
cat /tmp/android-envd-e2e-*/cubeshim-tail.txt
wc -c /tmp/android-envd-e2e-*/template-logs/stderr
```
