# e2b-code-interpreter 离线 wheel 包（鲲鹏 aarch64 / Python 3.12）

本目录包含在 x86 联网机上用 `pip download --platform manylinux2014_aarch64` 交叉下载的 **完整依赖**，
已在 PyPI 侧校验包含 `pyqwest`、`protobuf-py-ext` 的 **aarch64 cp312** wheel。

## 文件

| 文件 | 说明 |
|------|------|
| `cube-python-wheels-py312-aarch64.tar.gz` | 29 个 wheel，解压后为 `quickstart-pkgs/` |
| `install-e2b-offline.sh` | 鲲鹏上一键安装脚本 |

> 大文件不在 git 中；请从 GitHub Release 下载，或在本机按 `README_KUNPENG.md` §3.6.1-A1/A2 自建。

## 下载（联网 PC → 拷到鲲鹏）

鲲鹏通常**无法访问 GitHub**，请在联网 PC 上下载后 `scp` 到鲲鹏：

```bash
# 联网 PC
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-python-wheels-py312-aarch64/cube-python-wheels-py312-aarch64.tar.gz
sha256sum cube-python-wheels-py312-aarch64.tar.gz
# 期望：
# 80c9ccd582cec6ecdca3c10f4b61215ee162f7f8c7c35e6f44d6461a947293fb

scp cube-python-wheels-py312-aarch64.tar.gz install-e2b-offline.sh root@<鲲鹏IP>:~/offline-pkgs/
```

Release 页：https://github.com/LOLHenry/CubeSandbox/releases/tag/cube-python-wheels-py312-aarch64

## 校验

```bash
sha256sum cube-python-wheels-py312-aarch64.tar.gz
# 期望：
# 80c9ccd582cec6ecdca3c10f4b61215ee162f7f8c7c35e6f44d6461a947293fb
```

## 鲲鹏安装

```bash
cd ~/offline-pkgs
tar xzf cube-python-wheels-py312-aarch64.tar.gz

export PATH="/usr/local/python3.12/bin:$PATH"   # 若 make altinstall
python3.12 -m venv ~/cube-demo/.venv
source ~/cube-demo/.venv/bin/activate

bash install-e2b-offline.sh

python -c "import e2b_code_interpreter; print('ok', e2b_code_interpreter.__version__)"
```

## 包含的主要包

- `e2b-code-interpreter` 2.9.0
- `e2b` 2.35.0
- `pyqwest` 0.7.0 (**aarch64**)
- `protobuf-py-ext` 0.1.1 (**aarch64**)
- `python-dotenv`, `rich` 及全部传递依赖（共 29 wheels）
