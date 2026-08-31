#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
DATA_CUBELET="/data/cubelet"
LOOPBACK_IMAGE="${LOOPBACK_IMAGE:-/data/cubelet-xfs.img}"
LOOPBACK_SIZE="${LOOPBACK_SIZE:-50G}"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "sudo $0" >&2; exit 1; }
command -v mkfs.xfs >/dev/null || { echo "install xfsprogs" >&2; exit 1; }
mkdir -p /data
if [[ ! -f "${LOOPBACK_IMAGE}" ]]; then
  truncate -s "${LOOPBACK_SIZE}" "${LOOPBACK_IMAGE}"
  mkfs.xfs -f -m reflink=1 "${LOOPBACK_IMAGE}"
fi
mkdir -p "${DATA_CUBELET}"
mountpoint -q "${DATA_CUBELET}" || mount -o loop,pquota "${LOOPBACK_IMAGE}" "${DATA_CUBELET}"
df -T "${DATA_CUBELET}"
