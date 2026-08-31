#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Provision dev-env guest + install one-click (KVM, CUBE_PVM_ENABLE=0).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEV_ENV="${REPO_ROOT}/dev-env"
WORK_DIR="${WORK_DIR:-${DEV_ENV}/.workdir}"
INTERNAL="${DEV_ENV}/internal"
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
USE_TCG="${USE_TCG:-1}"
MARKER="${WORK_DIR}/.guest-provisioned"

log() { printf '[m0-provision] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

ssh_g() {
  sshpass -p "${VM_PASSWORD}" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ConnectTimeout=15 -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" "$@"
}
scp_g() {
  sshpass -p "${VM_PASSWORD}" scp \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -P "${SSH_PORT}" "$@"
}

[[ -e /dev/kvm ]] || die "no /dev/kvm"
sudo chmod 666 /dev/kvm 2>/dev/null || true
pkill -9 -f qemu-system-x86 2>/dev/null || true
sleep 1
rm -f "${WORK_DIR}/qemu.pid"

QCOW2="$(ls "${WORK_DIR}"/OpenCloudOS-*.qcow2 2>/dev/null | head -1)"
[[ -n "${QCOW2}" && -f "${QCOW2}" ]] || die "qcow2 missing — download via prepare_image first"

log "starting VM (USE_TCG=${USE_TCG}; OVMF; CUBE_PVM_ENABLE=0 path)"
USE_TCG="${USE_TCG}" VM_MEMORY_MB="${VM_MEMORY_MB}" "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/run-dev-vm-ovmf.sh"
[[ "$(pgrep -c qemu-system-x86 || echo 0)" -le 1 ]] || die "multiple qemu instances — abort"

log "waiting for SSH (TCG may take 2–3 min)..."
for _ in $(seq 1 120); do
  ssh_g 'true' >/dev/null 2>&1 && break
  sleep 5
done
ssh_g 'true' >/dev/null 2>&1 || die "SSH timeout"

if [[ ! -f "${MARKER}" ]]; then
  for script in grow_rootfs.sh setup_selinux.sh setup_path.sh setup_banner.sh setup_autostart.sh; do
    scp_g "${INTERNAL}/${script}" "${VM_USER}@127.0.0.1:~/${script}"
    ssh_g "chmod +x ~/${script} && ~/${script}"
    log "ran ${script}"
  done
  touch "${MARKER}"
  log "guest provisioned; shutting down VM"
  ssh_g 'sudo shutdown -h now' >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do pgrep qemu-system-x86 >/dev/null || break; sleep 2; done
  pkill -9 -f qemu-system-x86 2>/dev/null || true
  rm -f "${WORK_DIR}/qemu.pid"
  log "rebooting VM for one-click install"
  "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/run-dev-vm-ovmf.sh"
  for _ in $(seq 1 60); do ssh_g 'true' >/dev/null 2>&1 && break; sleep 5; done
fi

log "installing one-click inside guest (CUBE_PVM_ENABLE=0)"
ssh_g 'sudo bash -s' <<'GUEST'
set -euo pipefail
export CUBE_PVM_ENABLE=0 MIRROR=cn
export CUBE_SANDBOX_NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')"
export CUBE_SANDBOX_NETWORK_CIDR=10.100.0.0/18
curl -sf http://127.0.0.1:3000/health && exit 0
curl -fsSL https://raw.githubusercontent.com/tencentcloud/CubeSandbox/master/deploy/one-click/online-install.sh | sudo bash
curl -sf http://127.0.0.1:3000/health
sudo /usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh
GUEST

curl -sf "http://127.0.0.1:13000/health" && log "M0 OK — CubeAPI :13000 WebUI :12088"
