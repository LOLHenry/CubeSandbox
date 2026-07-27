#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGS="${ROOT}/quickstart-pkgs"

if [[ ! -d "${PKGS}" ]]; then
  echo "missing ${PKGS}; extract cube-python-wheels-py312-aarch64.tar.gz first" >&2
  exit 1
fi

if ! ls "${PKGS}"/pyqwest-*aarch64*.whl >/dev/null 2>&1; then
  echo "pyqwest aarch64 wheel not found in ${PKGS}" >&2
  exit 1
fi

python -V
pip install --no-index --find-links="${PKGS}" \
  e2b-code-interpreter python-dotenv rich

echo "installed:"
python -c "import e2b_code_interpreter; print(e2b_code_interpreter.__version__)"
