#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Collect ADB fingerprint from existing AGR mobile instance.
set -euo pipefail

INSTANCE_ID="${1:-}"
AGR_BIN="${AGR_BIN:-agr}"
OUT_DIR="${2:-/tmp/agr-fingerprint-$(date +%Y%m%d-%H%M%S)}"

[[ -n "$INSTANCE_ID" ]] || { echo "Usage: $0 <instance-id> [out-dir]" >&2; exit 2; }

mkdir -p "$OUT_DIR"
"$AGR_BIN" instance mobile connect "$INSTANCE_ID" -o json | tee "$OUT_DIR/connect.json"

cmds=(
  "getprop"
  "getprop | grep -iE 'redroid|smartrun|qemu|cuttlefish|gralloc'"
  "cat /sys/class/dmi/id/sys_vendor; cat /sys/class/dmi/id/product_name"
  "uname -a"
  "ps -A | grep -iE 'envd|appium|adbd|redroid'"
  "ss -lntp"
)

for i in "${!cmds[@]}"; do
  c="${cmds[$i]}"
  echo ">>> $c"
  "$AGR_BIN" instance mobile adb "$INSTANCE_ID" -- shell "$c" | tee "$OUT_DIR/cmd_${i}.txt" || true
done

echo "Saved to $OUT_DIR"
