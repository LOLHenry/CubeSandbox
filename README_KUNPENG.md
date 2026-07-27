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

说明：`.env` 给 `install.sh` 读；装完后运行时以  
`/usr/local/services/cubetoolbox/.one-click.env` 为准。改后者后需 `systemctl restart`。

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

## 2. 下一步：制作模板（安装成功后必做）

平台起来后还没有可启动的沙箱模板，需要先做模板：

```bash
cubemastercli tpl create-from-image \
  --image cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest \
  --writable-layer-size 1G \
  --expose-port 49999 \
  --expose-port 49983 \
  --probe 49999
```

记下 `job_id`：

```bash
cubemastercli tpl watch --job-id <job_id>
```

等到状态 **`READY`**，记录 **`template_id`**（后面所有创建沙箱都要用）。

> 若本机已 `load` 了 `sandbox-code:latest`，创建模板时不必再从外网拉该镜像。

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

### 3.2 方式 A：Python SDK（推荐）

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

创建沙箱（只要 ID、自行管理生命周期）：

```python
import os
from e2b_code_interpreter import Sandbox

sbx = Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"])
print("sandbox_id =", sbx.sandbox_id)
# ... 使用 sbx ...
sbx.kill()
```

### 3.3 方式 B：HTTP REST（兼容 E2B）

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

### 3.4 调用链（便于理解）

```text
客户端 / SDK / curl
  → CubeAPI :3000          （创建沙箱等控制面 API）
    → CubeMaster           （调度）
      → Cubelet            （本机拉起 MicroVM）
  → CubeProxy / *.cube.app （访问沙箱内服务端口）
```

---

## 4. 防火墙放行（另一台机器访问本机）

单机部署、另一台机器通过网络访问时，用 **firewalld**（OpenCloudOS / CentOS / RHEL / 多数鲲鹏机常见）放行以下端口。

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

### 4.4 远端自检

```bash
curl -sS "http://<鲲鹏IP>:3000/health"
curl -kI "https://<鲲鹏IP>/"
# WebUI（若启用）
curl -sS -o /dev/null -w "%{http_code}\n" "http://<鲲鹏IP>:12088/"
```

客户端环境变量示例：

```bash
export E2B_API_URL="http://<鲲鹏IP>:3000"
export E2B_API_KEY="e2b_000000"
export CUBE_TEMPLATE_ID="<你的 template_id>"
export SSL_CERT_FILE="/path/to/rootCA.pem"   # 从鲲鹏拷贝 mkcert 根证，若走 HTTPS
```

> 若系统没有 firewalld，可用 `iptables` / `ufw` 放行同样端口；云厂商安全组也需同步放行 3000/80/443（及可选 12088）。

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

---

## 6. 建议操作清单（你现在的进度）

- [x] 下载 one-click arm64 包并解压  
- [x] 下载并解压离线 Docker arm64 镜像包  
- [ ] `sudo bash ./load-images.sh`，确认 `Architecture=arm64`  
- [ ] `.env` / `.one-click.env` 中 `MIRROR=cn`  
- [ ] DNS：必要时 `CUBE_PROXY_DNSMASQ_MODE=standalone`  
- [ ] firewalld 放行 3000/80/443（及可选 12088）  
- [ ] `sudo bash ./install.sh` 或 `systemctl restart` + `quickcheck` 通过  
- [ ] `cubemastercli tpl create-from-image` → 模板 `READY`  
- [ ] 用 SDK 或 `POST /sandboxes` 创建沙箱并 `run_code`  

完成「导入镜像」后，从第 **1.4 / 2 / 3 / 4** 节继续即可。

---

## 7. 相关链接

| 说明 | 链接 |
|------|------|
| 官方裸金属部署 | [docs/zh/guide/bare-metal-deploy.md](docs/zh/guide/bare-metal-deploy.md) |
| 官方 ARM 支持说明 | [docs/zh/blog/posts/2026-07-08-cubesandbox-arm-support.md](docs/zh/blog/posts/2026-07-08-cubesandbox-arm-support.md) |
| one-click arm64 包 | GitHub / CNB Releases 中的 `cube-sandbox-one-click-*-arm64.tar.gz` |
| 离线 Docker arm64 包 | https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-docker-arm64-v0.6.0 |
