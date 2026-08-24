# 鲲鹏离线安装逐步指南

## 阶段 0：准备

1. **CubeSandbox v0.6.0 arm64** one-click 已安装（cubemaster + cubelet + network-agent）。
2. 主机 **aarch64**，`ls -l /dev/kvm` 存在。
3. `/data/cubelet` 为 XFS（one-click 默认）。
4. 将 `agr-mobile-replication-kit-kunpeng-arm64.tar.gz` 拷入离线机。

## 阶段 1：解压

```bash
sudo ./scripts/02-install-offline-kit.sh agr-mobile-replication-kit-kunpeng-arm64.tar.gz
source /opt/agr-mobile-replication-kit-kunpeng-arm64/kit.env
cp configs/env.kunpeng.example .env
# 按需编辑 CUBEMASTER_URL 等
```

## 阶段 2：编译镜像

```bash
export PATH=/usr/local/go/bin:$PATH
./scripts/03-build-image.sh
./scripts/04-verify-image.sh
```

期望：
- `file out/envd`（或容器内）含 `interpreter /system/bin/linker64`
- `envd /health` → 204

## 阶段 3：建模板

```bash
source .env
./scripts/05-create-template.sh
```

**务必** `--cpu 4000 --memory 6144`（脚本默认已设）。2GiB 会导致 Android 起不来。

## 阶段 4：起沙箱并打通外网

1. `cubemastercli run -t <template-id>`
2. `cubemastercli info -s <sandbox-id>` 查看 `host_port`
3. 若集群外访问：
   - envd: `curl http://<node-ip>:<host_port_for_49983>/health`
   - adb: `adb connect <node-ip>:<host_port_for_5555>`
4. network-agent 需 `--host-proxy-bind-ip=0.0.0.0`（见 CubeSandbox 文档）

## 阶段 5：与 AGR 云端对照（可选，需凭据）

在能访问公网的机器：

```bash
export TENCENTCLOUD_SECRET_ID=...
export TENCENTCLOUD_SECRET_KEY=...
export AGR_REGION=ap-shanghai
./probe/agr-probe-mobile.sh
./probe/agr-collect-fingerprint.sh <instance-id>
```

对比 `getprop` / DMI / 监听端口与鲲鹏副本差异。

## 常见问题

| 现象 | 处理 |
|------|------|
| `go build` VCS 错误 | 脚本已带 `-buildvcs=false` |
| Dockerfile 拉 buildkit syntax | 使用 `DOCKER_BUILDKIT=0` + `Dockerfile.inject` |
| 模板 49983 refused | 检查 envd 是否为 Android ELF，非 Linux static |
| adb 连不上 | 加大内存；检查 privileged；检查 host_port 防火墙 |
