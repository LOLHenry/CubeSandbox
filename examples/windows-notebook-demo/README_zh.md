# Windows Jupyter 远程演示 CubeSandbox

在 **Windows 本机** 用 Jupyter Notebook 逐格调用鲲鹏上的 CubeSandbox（控制面 API + 沙箱内 `run_code`）。  
Jupyter 只是遥控器；计算与隔离在鲲鹏 MicroVM 里。

英文说明见 [README.md](README.md)。

## 1. 鲲鹏根证书在哪里

one-click 安装会用 **mkcert** 签发 `*.cube.app` 证书。客户端走 HTTPS / CubeProxy 时需要这份**根证**。

### 默认路径（root 安装）

```text
/root/.local/share/mkcert/rootCA.pem
```

同目录通常还有 `rootCA-key.pem`（**私钥，不要拷到 Windows，不要外传**）。你只需要 `rootCA.pem`。

### 在鲲鹏上确认

```bash
# 推荐：问 mkcert 实际 CAROOT
mkcert -CAROOT
# 常见输出：/root/.local/share/mkcert

ls -l "$(mkcert -CAROOT)/rootCA.pem"

# 若未在 PATH：
/usr/local/bin/mkcert -CAROOT
# 或安装包内置：
/usr/local/services/cubetoolbox/support/bin/mkcert -CAROOT
```

### 拷到 Windows

```bash
# 在鲲鹏上（示例：scp 到 Windows）
scp /root/.local/share/mkcert/rootCA.pem user@windows-host:C:/certs/cube-rootCA.pem
```

或用 WinSCP / U 盘：只复制 `rootCA.pem` → 例如 `C:\certs\cube-rootCA.pem`。

> 业务证书（`cube.app+3.pem` 等）在  
> `/usr/local/services/cubetoolbox/cubeproxy/certs/`，  
> **那不是根证**；Windows 侧 `SSL_CERT_FILE` 要指向 **rootCA.pem**。

---

## 2. 前置条件

- 鲲鹏已 `install complete`，模板 `READY`
- firewalld 已放行 `3000/80/443`（可选 `12088`），见仓库根目录 `README_KUNPENG.md` §4
- Windows 能访问：`http://10.50.156.199:3000/health`（按实际 IP 改）
- Windows 已装 Python 3.10+

---

## 3. Windows 搭建 Jupyter

PowerShell：

```powershell
python -m venv C:\venv\cube-demo
C:\venv\cube-demo\Scripts\Activate.ps1

cd <本示例目录>
pip install -r requirements.txt
python -m ipykernel install --user --name cube-demo --display-name "Cube Sandbox Demo"

copy .env.example .env
# 编辑 .env：填 CUBE_TEMPLATE_ID、IP、SSL_CERT_FILE 路径

jupyter lab
```

浏览器打开后，新建或打开 `cube_sandbox_demo.ipynb`，内核选 **Cube Sandbox Demo**。

---

## 4. Notebook 演示顺序

按单元格依次 Run：

| Cell | 作用 |
|------|------|
| 1 | 加载 `.env`，打印连接配置 |
| 2 | `Sandbox.create` → 打印 `sandbox_id` |
| 3 | `run_code`：架构 / Python 版本 |
| 4 | 探测 numpy / pandas / matplotlib / sklearn |
| 5 | 简单计算（证明在沙箱内执行） |
| 6 | `commands.run` 跑 Shell（可选） |
| 7 | `sbx.kill()` 销毁 |

不要提前 kill；Cell 2～6 共用同一个 `sbx`。

---

## 5. 说明

- `sandbox-code` 是 Code Interpreter 运行时，**不保证**自带 pandas/numpy；以 Cell 4 为准。
- 需要完整数据科学栈时，另做带预装包的镜像/模板（见 `README_KUNPENG.md` §3.2）。
- 演示主路径用 SDK 即可；浏览器打开 `*.cube.app` 还需 DNS/hosts + 信任该根证。
