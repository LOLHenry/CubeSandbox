# 鲲鹏本机 Jupyter 演示 CubeSandbox

在 **鲲鹏主机上** 用 Jupyter Notebook 逐格调用本机 CubeSandbox（`run_code` / `commands.run`）。  
客户端与沙箱在同一台机器上，**无需** Windows hosts、`CUBE_PROXY_NODE_IP` 或 Acrylic DNS。

英文说明：[README.md](README.md)

## 1. 前置条件

- one-click 已 `install complete`
- 模板 `READY`（`sandbox-code` + `49999/49983`）
- Python 3.10+（建议 3.11 / 3.12）

```bash
systemctl is-active cube-sandbox-control.target
curl -sS http://127.0.0.1:3000/health
cubemastercli tpl list
```

## 2. mkcert 根证（本机）

```bash
mkcert -CAROOT
ls -l "$(mkcert -CAROOT)/rootCA.pem"
# 常见：/root/.local/share/mkcert/rootCA.pem
```

## 3. 环境配置

```bash
cd examples/kunpeng-notebook-demo
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
python -m ipykernel install --user --name kunpeng-cube-demo --display-name "Kunpeng Cube Demo"

cp .env.example .env
# 编辑 .env，填写 CUBE_TEMPLATE_ID
```

`.env` 示例：

```bash
E2B_API_URL=http://127.0.0.1:3000
E2B_API_KEY=e2b_000000
CUBE_TEMPLATE_ID=<READY 的 template_id>
SSL_CERT_FILE=/root/.local/share/mkcert/rootCA.pem
REQUESTS_CA_BUNDLE=/root/.local/share/mkcert/rootCA.pem
```

## 4. 启动 Jupyter

```bash
source .venv/bin/activate
jupyter lab --ip=127.0.0.1 --port=8888 --no-browser
```

SSH 到鲲鹏后，在本地浏览器做端口转发：

```bash
ssh -L 8888:127.0.0.1:8888 root@<鲲鹏IP>
```

浏览器打开 `http://127.0.0.1:8888`，打开 `cube_sandbox_demo.ipynb`，内核选 **Kunpeng Cube Demo**，按 Cell 1→7 运行。

## 5. 命令行快速验证（不用 Notebook）

```bash
source .venv/bin/activate
export $(grep -v '^#' .env | xargs)

python3 - <<'PY'
import os
from e2b_code_interpreter import Sandbox

with Sandbox.create(template=os.environ["CUBE_TEMPLATE_ID"], timeout=600) as sbx:
    print("sandbox_id =", sbx.sandbox_id)
    print(sbx.run_code("import platform; print(platform.machine())"))
    print(sbx.commands.run("uname -a").stdout)
PY
```

## 6. 复用同一沙箱

同一 Notebook 进程内保留 `sbx` 对象即可；不要每个 cell 都 `Sandbox.create()`。演示结束再 `sbx.kill()`。

## 7. 说明

- 本机已有 `*.cube.app` DNS（one-click 的 CoreDNS/dnsmasq），一般不会出现远程 Windows 上的 `getaddrinfo failed`。
- `sandbox-code` 不保证带 pandas/numpy；用 Cell 4 探测。
- 更多部署细节见仓库根目录 `README_KUNPENG.md`。
