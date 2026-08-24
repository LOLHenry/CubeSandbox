#!/usr/bin/env bash
# Install Go toolchain from the offline kit (linux/arm64).
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_TARBALL="$(ls "${KIT_ROOT}"/go/go*.linux-arm64.tar.gz | head -1)"
INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local}"

if [[ -z "${GO_TARBALL}" || ! -f "${GO_TARBALL}" ]]; then
  echo "ERROR: Go tarball not found under ${KIT_ROOT}/go/" >&2
  exit 1
fi

echo "==> Installing Go from $(basename "${GO_TARBALL}") to ${INSTALL_DIR}"
sudo rm -rf "${INSTALL_DIR}/go"
sudo tar -C "${INSTALL_DIR}" -xzf "${GO_TARBALL}"

export PATH="${INSTALL_DIR}/go/bin:${PATH}"
grep -q 'go/bin' "${HOME}/.bashrc" 2>/dev/null || \
  echo 'export PATH=/usr/local/go/bin:$PATH' >> "${HOME}/.bashrc"

go version
echo "OK: Go installed. Run: export PATH=${INSTALL_DIR}/go/bin:\$PATH"
