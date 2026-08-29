#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="${SCRIPT_DIR}/bin/containerd-shim-cube-rs"

DEFAULT_DEST="/usr/local/services/cubetoolbox/cube-shim/bin/containerd-shim-cube-rs"
DEST="${1:-$DEFAULT_DEST}"

if [[ ! -f "$SRC_BIN" ]]; then
  echo "ERROR: missing $SRC_BIN" >&2
  exit 1
fi

if ! file "$SRC_BIN" | grep -q 'ARM aarch64'; then
  echo "ERROR: binary is not aarch64: $(file -b "$SRC_BIN")" >&2
  exit 1
fi

DEST_DIR="$(dirname "$DEST")"
mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]]; then
  BAK="${DEST}.bak.$(date +%Y%m%d%H%M%S)"
  echo "==> Backup existing shim to $BAK"
  cp -a "$DEST" "$BAK"
fi

echo "==> Install $SRC_BIN -> $DEST"
install -m 0755 "$SRC_BIN" "$DEST"

if [[ -e /usr/local/bin/containerd-shim-cube-rs ]]; then
  echo "==> Refresh /usr/local/bin/containerd-shim-cube-rs"
  install -m 0755 "$SRC_BIN" /usr/local/bin/containerd-shim-cube-rs
fi

echo "OK: installed $(file -b "$DEST")"
echo "Next: systemctl restart cubelet && start a NEW ReDroid sandbox"
