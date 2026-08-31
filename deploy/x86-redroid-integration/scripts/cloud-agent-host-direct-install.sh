#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Cloud Agent host-direct install: real KVM, XFS loopback under /data/cubelet.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOOPBACK_IMAGE="${LOOPBACK_IMAGE:-/data/cubelet-xfs.img}"
LOOPBACK_SIZE="${LOOPBACK_SIZE:-50G}"
DATA_CUBELET="/data/cubelet"

log() { printf '[host-direct] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

[[ -e /dev/kvm ]] || die "no /dev/kvm on host"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run with sudo"

command -v mkfs.xfs >/dev/null || apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xfsprogs

mkdir -p /data
if [[ ! -f "${LOOPBACK_IMAGE}" ]]; then
  log "create loopback ${LOOPBACK_IMAGE} (${LOOPBACK_SIZE})"
  truncate -s "${LOOPBACK_SIZE}" "${LOOPBACK_IMAGE}"
  mkfs.xfs -f -m reflink=1 "${LOOPBACK_IMAGE}"
fi
mkdir -p "${DATA_CUBELET}"
if ! mountpoint -q "${DATA_CUBELET}"; then
  mount -o loop,pquota "${LOOPBACK_IMAGE}" "${DATA_CUBELET}"
fi
df -T "${DATA_CUBELET}"

export CUBE_PVM_ENABLE=0
export MIRROR=cn
export CUBE_SANDBOX_NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')"
export CUBE_SANDBOX_NETWORK_CIDR="${CUBE_SANDBOX_NETWORK_CIDR:-10.100.0.0/18}"
export CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false

if curl -sf http://127.0.0.1:3000/health >/dev/null 2>&1; then
  log "CubeSandbox already running"
else
  log "online-install one-click v0.7"
  curl -fsSL https://raw.githubusercontent.com/tencentcloud/CubeSandbox/master/deploy/one-click/online-install.sh \
    | bash -s -- --skip-precheck
fi

curl -sf http://127.0.0.1:3000/health || die "health check failed"
/usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh || true
log "host-direct M0 OK"
