#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="${SCRIPT_DIR}/bin/cube-agent"
DEFAULT_IMG="/usr/local/services/cubetoolbox/cube-image/cube-guest-image-cpu.img"
IMG="${1:-$DEFAULT_IMG}"

if [[ ! -f "$SRC_BIN" ]]; then
  echo "ERROR: missing $SRC_BIN (build aarch64 musl cube-agent first)" >&2
  exit 1
fi

if ! file "$SRC_BIN" | grep -q 'ARM aarch64'; then
  echo "ERROR: binary is not aarch64: $(file -b "$SRC_BIN")" >&2
  exit 1
fi

if [[ ! -f "$IMG" ]]; then
  echo "ERROR: guest image not found: $IMG" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

require_cmd losetup
require_cmd mount
require_cmd umount

WORK="$(mktemp -d)"
cleanup() {
  if mountpoint -q "$WORK/mnt" 2>/dev/null; then
    umount "$WORK/mnt" || true
  fi
  if [[ -n "${LOOP:-}" ]] && losetup "$LOOP" >/dev/null 2>&1; then
    losetup -d "$LOOP" || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

BAK="${IMG}.bak.$(date +%Y%m%d%H%M%S)"
echo "==> Backup guest image to $BAK"
cp -a "$IMG" "$BAK"

mkdir -p "$WORK/mnt"
LOOP="$(losetup --find --show --partscan "$IMG")"
PART="${LOOP}p1"
if [[ ! -b "$PART" ]]; then
  PART="$LOOP"
fi

mount "$PART" "$WORK/mnt"
DEST="$WORK/mnt/sbin/init"
if [[ ! -f "$DEST" ]]; then
  echo "ERROR: $DEST not found in guest image (unexpected layout)" >&2
  exit 1
fi

echo "==> Install $SRC_BIN -> $DEST"
install -m 0755 "$SRC_BIN" "$DEST"
sync
umount "$WORK/mnt"
losetup -d "$LOOP"
LOOP=""

echo "OK: patched guest image $(file -b "$SRC_BIN")"
echo "Next: systemctl restart cube-sandbox-cubelet.service && start a NEW ReDroid sandbox"
