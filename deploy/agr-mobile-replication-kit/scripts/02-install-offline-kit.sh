#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install unified tarball on offline Kunpeng host.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/agr-mobile-replication-kit-kunpeng-arm64}"
TARBALL="${1:-}"

if [[ -z "$TARBALL" ]]; then
  TARBALL="$(ls -1 "${ROOT}/dist/"agr-mobile-replication-kit-kunpeng-arm64.tar.gz 2>/dev/null | head -1 || true)"
fi

if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
  echo "Usage: $0 [path/to/agr-mobile-replication-kit-kunpeng-arm64.tar.gz]" >&2
  exit 1
fi

echo "==> Installing to ${INSTALL_DIR}"
sudo mkdir -p "$(dirname "$INSTALL_DIR")"
sudo rm -rf "$INSTALL_DIR"
sudo tar xzf "$TARBALL" -C "$(dirname "$INSTALL_DIR")"
sudo mv "$(dirname "$INSTALL_DIR")/$(basename "$TARBALL" .tar.gz)" "$INSTALL_DIR" 2>/dev/null || true

# tarball root name may match inner dir
if [[ ! -f "${INSTALL_DIR}/MANIFEST.json" ]]; then
  INNER="$(tar tzf "$TARBALL" | head -1 | cut -d/ -f1)"
  sudo mv "$(dirname "$INSTALL_DIR")/${INNER}" "$INSTALL_DIR"
fi

echo "export KIT_ROOT=${INSTALL_DIR}" | sudo tee "${INSTALL_DIR}/kit.env"
echo "Installed. Source: source ${INSTALL_DIR}/kit.env"
