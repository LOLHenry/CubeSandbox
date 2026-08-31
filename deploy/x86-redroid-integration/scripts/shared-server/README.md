# 共用服务器部署（fangyu 个人目录）

在 **121.37.54.41** 等共用机器上，所有文件仅写入 `~/cube-redroid-work/`，不在 `/data`、不修改系统环境变量/库、不访问其他用户目录。

## Cloud Agent 连不上时

从 Cursor Cloud Agent 实测：**SSH 22 端口超时**（ICMP 通，443 开但非 SSH）。需在服务器防火墙/安全组放行 Cloud Agent 出口 IP：

- `18.118.243.20`
- `16.58.218.29`

或在服务器上**本地执行**下方脚本，完成后把 `~/cube-redroid-work/assess-report.txt` 发回。

## 1. 仅评估（只读 + 写报告到个人目录）

```bash
mkdir -p ~/cube-redroid-work
curl -fsSL -o ~/cube-redroid-work/00-assess.sh \
  https://raw.githubusercontent.com/LOLHenry/CubeSandbox/cursor/x86-redroid-integration-5222/deploy/x86-redroid-integration/scripts/shared-server/00-assess.sh
bash ~/cube-redroid-work/00-assess.sh
cat ~/cube-redroid-work/assess-report.txt
```

## 2. 全流程（x86_64 + KVM 推荐）

```bash
curl -fsSL -o ~/cube-redroid-work/01-deploy-all-in-home.sh \
  https://raw.githubusercontent.com/LOLHenry/CubeSandbox/cursor/x86-redroid-integration-5222/deploy/x86-redroid-integration/scripts/shared-server/01-deploy-all-in-home.sh
curl -fsSL -o ~/cube-redroid-work/00-assess.sh \
  https://raw.githubusercontent.com/LOLHenry/CubeSandbox/cursor/x86-redroid-integration-5222/deploy/x86-redroid-integration/scripts/shared-server/00-assess.sh
chmod +x ~/cube-redroid-work/*.sh
bash ~/cube-redroid-work/01-deploy-all-in-home.sh 2>&1 | tee ~/cube-redroid-work/deploy.log
```

## 3. 反向 SSH（可选，让 Cloud Agent 继续操作）

在**服务器上**执行（将 `<CLOUD_AGENT_IP>` 换为当前 Agent 出口 IP）：

```bash
ssh -N -R 2222:localhost:22 fangyu@<CLOUD_AGENT_IP>
```

Agent 侧：`ssh -p 2222 fangyu@127.0.0.1`

## 架构说明

| 层级 | 路径 | 说明 |
|------|------|------|
| 宿主机 | `~/cube-redroid-work/` | 仓库、qcow2、离线包、日志 |
| dev-env VM | guest 内 `/usr/local/services/...` | one-click 装在**虚机内**，不污染共用宿主机 |

若机器为 **aarch64**（密码 hint ARMNative），应走 arm64 ReDroid 原生路径，不要用 x86 QEMU 虚机。

## 前置条件

- `fangyu` 可用 `docker`
- `/dev/kvm` 可读写（或管理员将用户加入 `kvm` 组）
- `~/` 剩余磁盘 ≥ 80GB，内存 ≥ 16GB（最低 8GB 仅够小 VM）
