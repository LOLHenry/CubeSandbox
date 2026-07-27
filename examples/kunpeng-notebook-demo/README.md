# Kunpeng local Jupyter demo for CubeSandbox

Run CubeSandbox cell-by-cell from **Jupyter on the Kunpeng host** (same machine as CubeAPI/CubeProxy).

Chinese guide (recommended): [README_zh.md](README_zh.md).

## Quick start

```bash
cd examples/kunpeng-notebook-demo
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # set CUBE_TEMPLATE_ID
jupyter lab --ip=127.0.0.1 --port=8888 --no-browser
```

Open `cube_sandbox_demo.ipynb` and run cells top to bottom.

No `CUBE_PROXY_NODE_IP` or hosts hacks needed when the client runs on the same host as the cluster.
