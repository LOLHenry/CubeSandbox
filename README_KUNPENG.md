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
**推荐路线：在鲲鹏本机跑 OpenClaw + `e2b-code-interpreter`**（同机 DNS 已通，无需 hosts / WSL / `CUBE_PROXY_NODE_IP`）。  
鲲鹏通常**无公网**，Python / Node / OpenClaw 包需在联网机下载后**离线安装**（§3.6）。

> `CUBE_PROXY_NODE_IP` 仅 **`cubesandbox`** SDK 支持；官方 OpenClaw skill 用的是 **`e2b-code-interpreter`**，同机跑即可直接解析 `*.cube.app`。

### 3.6 鲲鹏本机跑 OpenClaw + e2b（推荐；无外网离线装包）

架构：

```text
鲲鹏本机
  ├─ CubeSandbox（已装）── DNS 已解析 *.cube.app
  ├─ Python venv + e2b-code-interpreter   ← 离线 wheel
  └─ Node.js + OpenClaw + cube-sandbox skill ← 离线 tar / npm 包
```

复用官方示例（不另造 demo）：

- [`examples/openclaw-integration/README_zh.md`](examples/openclaw-integration/README_zh.md)
- [`examples/code-sandbox-quickstart/README_zh.md`](examples/code-sandbox-quickstart/README_zh.md)

#### 3.6.1 离线包清单（联网机下载 → 拷到鲲鹏）

在一台**能访问公网**的机器上准备下列文件，再 `scp` / U 盘拷到鲲鹏（例如 `~/offline-pkgs/`）。

| 包 | 用途 | 架构注意 |
|----|------|----------|
| `e2b-pkgs/`（pip wheel 目录） | `e2b-code-interpreter` + 依赖 | **必须是 aarch64 / cp312** |
| `quickstart-pkgs/`（可选） | `python-dotenv`、`rich` 等 | 同上 |
| `node-*-linux-arm64.tar.xz` | OpenClaw 运行时 | Node **22+**，选 **linux-arm64** |
| `openclaw-bundle-linux-arm64.tar.gz` | `openclaw` CLI + `node_modules` | 在 **aarch64 Linux** 上打包装最稳 |

**强烈建议：联网下载机也用 aarch64 Linux**（另一台鲲鹏临时开网、云 ARM VM、或本机 WSL 里的 qemu 均可）。  
若只能在 **x86/Windows** 上下载 Python 包，必须加平台参数（见下），且 **OpenClaw/npm 仍建议在 aarch64 上打包**（`sharp` 等原生模块与 CPU 绑定）。

在鲲鹏上先确认 Python 版本（建议 3.12）：

```bash
python3 --version
# 若无 3.12：用系统包管理器安装 python3.12 / python3.12-venv（离线 rpm/deb 另备）
```

##### A. Python：`e2b-code-interpreter`（在**联网 aarch64** 上）

```bash
mkdir -p e2b-pkgs quickstart-pkgs
python3.12 -m pip download e2b-code-interpreter -d ./e2b-pkgs/
python3.12 -m pip download e2b-code-interpreter python-dotenv rich -d ./quickstart-pkgs/
# 可选：jupyterlab ipykernel
tar czf cube-python-wheels-aarch64.tar.gz e2b-pkgs quickstart-pkgs
```

若联网机是 **x86**，强制下 aarch64 wheel（无对应二进制的包会失败，此时改用 aarch64 机下载）：

```bash
python3 -m pip download e2b-code-interpreter \
  --platform manylinux2014_aarch64 \
  --platform linux_aarch64 \
  --python-version 312 \
  --implementation cp \
  --abi cp312 \
  --only-binary=:all: \
  -d ./e2b-pkgs/
```

##### B. Node.js arm64（任意联网机浏览器 / curl）

从 https://nodejs.org/dist/ 选 **linux-arm64**，例如：

```bash
NODE_VER=v22.22.3
curl -fLO "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-arm64.tar.xz"
# 校验 sha256 见同目录 SHASUMS256.txt
```

##### C. OpenClaw npm 包（务必在**联网 aarch64 Linux** 上）

```bash
# 假设已解压并把 node 的 bin 加入 PATH
node -v   # v22+
npm -v

mkdir -p openclaw-bundle && cd openclaw-bundle
npm init -y
npm install openclaw@latest
# 确认 CLI 可用
./node_modules/.bin/openclaw --version
cd ..
tar czf openclaw-bundle-linux-arm64.tar.gz -C openclaw-bundle .
```

把下列文件拷到鲲鹏 `~/offline-pkgs/`：

```text
cube-python-wheels-aarch64.tar.gz   # 或散开的 e2b-pkgs/
node-v22.*-linux-arm64.tar.xz
openclaw-bundle-linux-arm64.tar.gz
```

> OpenClaw **对话模型**还需能访问的 LLM API（内网 OpenAI 兼容端点 / 厂商内网网关均可）。  
> 这与「装包不上公网」是两件事：包可离线装；模型地址填你环境可达的内网 URL。

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

#### 3.6.4 鲲鹏离线安装 Python + e2b

```bash
cd ~/offline-pkgs
tar xzf cube-python-wheels-aarch64.tar.gz   # 若已是目录可跳过

python3.12 -m venv ~/cube-demo/.venv
source ~/cube-demo/.venv/bin/activate
python -V    # 期望 3.12.x

pip install --no-index --find-links=./e2b-pkgs/ e2b-code-interpreter
# quickstart 额外依赖：
# pip install --no-index --find-links=./quickstart-pkgs/ python-dotenv rich
```

验证导入：

```bash
python -c "import e2b_code_interpreter; print('ok', e2b_code_interpreter.__version__)"
```

#### 3.6.5 最小 SDK 验证（先于 OpenClaw）

```bash
source ~/cube-demo/.venv/bin/activate
# 已 export §3.6.3 变量

python3 - <<'PY'
import os
from e2b_code_interpreter import Sandbox

with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"], timeout=600) as sbx:
    print("sandbox_id =", sbx.sandbox_id)
    print(sbx.run_code("import platform; print(platform.machine())"))
    print(sbx.commands.run("uname -a").stdout)
PY
```

期望沙箱内 `platform.machine()` 为 **`aarch64`**。  
此步失败时先不要装 OpenClaw——问题在 Cube / 模板 / DNS / 证书，与 OpenClaw 无关。

#### 3.6.6 鲲鹏离线安装 Node.js + OpenClaw

```bash
cd ~/offline-pkgs

# Node → 例如装到 /usr/local（需 root）或 ~/node
sudo tar -xJf node-v22.*-linux-arm64.tar.xz -C /usr/local --strip-components=1
node -v
npm -v

# OpenClaw bundle
mkdir -p ~/openclaw-app
tar xzf openclaw-bundle-linux-arm64.tar.gz -C ~/openclaw-app
echo 'export PATH="$HOME/openclaw-app/node_modules/.bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
openclaw --version
```

按官方流程初始化（模型 API 填**内网可达**地址）：

```bash
openclaw onboard --install-daemon
# 或先：openclaw gateway status
```

安装 Cube skill：

```bash
# 仓库已在鲲鹏上时：
cp -r /path/to/CubeSandbox/examples/openclaw-integration/skills/cube-sandbox/ \
  ~/.openclaw/workspace/skills/

# OpenClaw 进程也要能读到 §3.6.3 的环境变量（systemd user 服务需写入
# Environment= 或 EnvironmentFile=；仅 export 到当前 shell 不够）
openclaw gateway restart
```

确认：

```bash
ls ~/.openclaw/workspace/skills/cube-sandbox/SKILL.md
```

示例话术：

- `在沙箱里跑一段 Python，计算 1 到 100 的和`
- `用沙箱执行 uname -a 并返回结果`
- `在完全断网的沙箱中运行这段代码`

#### 3.6.7 可选：`code-sandbox-quickstart`（离线）

```bash
source ~/cube-demo/.venv/bin/activate
pip install --no-index --find-links=~/offline-pkgs/quickstart-pkgs/ \
  e2b-code-interpreter python-dotenv rich

cd /path/to/CubeSandbox/examples/code-sandbox-quickstart
cp .env.example .env
# E2B_API_URL=http://127.0.0.1:3000
# CUBE_TEMPLATE_ID=...
python exec_code.py
python cmd.py
```

WebUI（可选）：`http://127.0.0.1:12088`

#### 3.6.8 离线装包排错

| 现象 | 处理 |
|------|------|
| `pip` 报 `No matching distribution` / 只有 `x86_64` wheel | 下载机架构不对；用 aarch64 重下，或加 `--platform ..._aarch64` |
| `npm` / `openclaw` 报 `sharp` / ELF 错误 | bundle 在 x86 上打的；必须在 aarch64 重打 `openclaw-bundle` |
| `Sandbox.create` 成功、`run_code` DNS 失败 | 本机 DNS：§5.1；确认未改坏 `/etc/resolv.conf` |
| Skill 触发但 SSL 失败 | `SSL_CERT_FILE` 指向 `$(mkcert -CAROOT)/rootCA.pem`，并写入 OpenClaw 服务环境 |
| OpenClaw 能起、对话超时 | 模型 API 外网不通；改配内网 endpoint，与离线装包无关 |
| 华为 PyPI 镜像缺 `e2b-code-interpreter` | 预期行为；不要依赖该镜像，走本节离线 wheel |

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
| `mirrors.tools.huawei.com/pypi/simple` 找不到 `e2b-code-interpreter` | 该内网镜像未同步此包；按 §3.6.1 在联网机（建议 aarch64）`pip download`，再在鲲鹏 `pip install --no-index --find-links=...` |
| `getaddrinfo failed` / `49999-*.cube.app` 解析失败 | 客户端不在集群 DNS 域内；**在鲲鹏本机跑 SDK / OpenClaw**（§3.6），不要从 Windows 远程当执行端 |
| `install.sh` 长时间无输出 | 多半在等 systemd；另开终端看 `systemctl list-jobs`。若已 `install complete`，不要反复全量安装，直接做模板 |

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

## 6. 建议操作清单（当前进度）

- [x] 下载 one-click arm64 包并解压  
- [x] 下载并解压离线 Docker arm64 镜像包 / `load-images.sh`  
- [x] `.env` / `.one-click.env`：`MIRROR=cn`；必要时 `CUBE_PROXY_DNSMASQ_MODE=standalone`  
- [x] `install.sh` → **`install complete`**  
- [ ] **`CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false` + 重启 cubemaster**（§2.0；两边 env 都写）  
- [ ] `docker tag ... sandbox-code:latest`，确认 `Architecture=arm64`  
- [ ] `tpl create-from-image --image sandbox-code:latest` → `READY`，记下 `template_id`  
- [ ] **离线装包**：§3.6.1 下载 aarch64 Python wheels + Node arm64 + OpenClaw bundle → 拷到鲲鹏  
- [ ] §3.6.4～3.6.5：离线装 e2b → 最小 `Sandbox.create` / `run_code` 通过  
- [ ] §3.6.6：离线装 OpenClaw + cube-sandbox skill（模型 API 用内网地址）  
- [ ] （可选）firewalld 放行 3000/80/443，供其他机器只访问 API/WebUI  

**当前下一步：§2.0 → 模板 READY → §3.6 离线装 e2b/OpenClaw → 本机演示。**

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
