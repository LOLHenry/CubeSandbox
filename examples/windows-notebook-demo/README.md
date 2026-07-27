# Windows Jupyter remote demo for CubeSandbox

Run CubeSandbox cell-by-cell from **Jupyter on Windows**, while sandboxes execute on Kunpeng.

Chinese guide (recommended): [README_zh.md](README_zh.md).

## Root CA on Kunpeng

```text
/root/.local/share/mkcert/rootCA.pem
```

Confirm with `mkcert -CAROOT`. Copy only `rootCA.pem` to Windows (e.g. `C:\certs\cube-rootCA.pem`). Do **not** copy `rootCA-key.pem`.

Leaf certs under `/usr/local/services/cubetoolbox/cubeproxy/certs/` are **not** the trust root.

## Quick start

```powershell
python -m venv C:\venv\cube-demo
C:\venv\cube-demo\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
# edit .env
jupyter lab
```

Open `cube_sandbox_demo.ipynb` and run cells top to bottom.
