#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M0 via dev-env: OpenCloudOS 9 KVM VM + one-click install (CUBE_PVM_ENABLE=0).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEV_ENV="${REPO_ROOT}/dev-env"
WORK_DIR="${WORK_DIR:-${DEV_ENV}/.workdir}"
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"
CUBE_API_PORT="${CUBE_API_PORT:-13000}"
WEB_UI_PORT="${WEB_UI_PORT:-12088}"
SKIP_PREPARE="${SKIP_PREPARE:-0}"
VM_MEMORY_MB="${VM_MEMORY_MB:-6144}"

log() { printf '[m0-dev-env] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

ensure_kvm_access() {
  if [[ ! -e /dev/kvm ]]; then
    die "/dev/kvm missing — KVM required (not PVM)"
  fi
  if ! [[ -r /dev/kvm && -w /dev/kvm ]]; then
    log "fixing /dev/kvm permissions (needs root once)"
    sudo chmod 666 /dev/kvm
  fi
  nested="$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null \
    || cat /sys/module/kvm_amd/parameters/nested 2>/dev/null || echo unknown)"
  log "KVM nested=${nested} (expect Y/1 for MicroVM inside guest)"
}

ssh_guest() {
  sshpass -p "${VM_PASSWORD}" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" "$@"
}

wait_ssh() {
  local deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    if ssh_guest 'true' >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  die "guest SSH not ready on port ${SSH_PORT}"
}

WRAP_DIR="${REPO_ROOT}/deploy/x86-redroid-integration/scripts/.path-wrap"
mkdir -p "${WRAP_DIR}"
ln -sf "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/ssh-sshpass-wrap.sh" "${WRAP_DIR}/ssh"
ln -sf "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/scp-sshpass-wrap.sh" "${WRAP_DIR}/scp"
export PATH="${WRAP_DIR}:${PATH}"
export DEV_ENV_VM_PASSWORD="${VM_PASSWORD}"

ensure_kvm_access

if [[ "${SKIP_PREPARE}" != "1" ]]; then
  log "prepare_image (download + guest init, ~10 min first time)"
  VM_MEMORY_MB="${VM_MEMORY_MB}" PATH="${WRAP_DIR}:${PATH}" DEV_ENV_VM_PASSWORD="${VM_PASSWORD}" \
    "${DEV_ENV}/prepare_image.sh" 2>&1 | tee /opt/cursor/artifacts/m0-prepare-image.log
fi

if [[ -f "${WORK_DIR}/qemu.pid" ]] && kill -0 "$(cat "${WORK_DIR}/qemu.pid")" 2>/dev/null; then
  log "QEMU already running pid=$(cat "${WORK_DIR}/qemu.pid")"
else
  log "starting dev VM (KVM, CUBE_PVM_ENABLE=0 path)"
  VM_MEMORY_MB="${VM_MEMORY_MB}" VM_BACKGROUND=1 "${DEV_ENV}/run_vm.sh"
fi

log "waiting for SSH..."
wait_ssh
log "guest SSH ready"

log "installing CubeSandbox one-click inside guest (native KVM, not PVM)"
ssh_guest 'sudo bash -s' <<'GUEST'
set -euo pipefail
export CUBE_PVM_ENABLE=0
export MIRROR=cn
# QEMU user networking — detect primary IP for cube-proxy / MinIO
NODE_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk "{print \$7; exit}")"
export CUBE_SANDBOX_NODE_IP="${NODE_IP:-10.0.2.15}"
export CUBE_SANDBOX_NETWORK_CIDR="${CUBE_SANDBOX_NETWORK_CIDR:-10.100.0.0/18}"

if [[ -d /usr/local/services/cubetoolbox ]] && curl -sf http://127.0.0.1:3000/health >/dev/null 2>&1; then
  echo "CubeSandbox already healthy"
  exit 0
fi

curl -fsSL "https://raw.githubusercontent.com/tencentcloud/CubeSandbox/master/deploy/one-click/online-install.sh" \
  | bash

curl -sf http://127.0.0.1:3000/health && echo " cube-api OK"
/usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh || true
GUEST

log "host-side checks via port forwards"
curl -sf "http://127.0.0.1:${CUBE_API_PORT}/health" && echo " forwarded cube-api OK" \
  || die "cube-api not reachable on host :${CUBE_API_PORT}"

log "M0 complete — WebUI http://127.0.0.1:${WEB_UI_PORT} SSH :${SSH_PORT}"
