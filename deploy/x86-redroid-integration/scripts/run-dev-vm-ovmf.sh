#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Start dev-env VM. Prefer KVM; fall back to TCG when nested KVM is broken (Cloud Agent).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV="$(cd "${SCRIPT_DIR}/../../.." && pwd)/dev-env"
WORK_DIR="${WORK_DIR:-${DEV_ENV}/.workdir}"
IMAGE="${IMAGE_PATH:-$(ls "${WORK_DIR}"/OpenCloudOS-*.qcow2 2>/dev/null | head -1)}"
SSH_PORT="${SSH_PORT:-10022}"
CUBE_API_PORT="${CUBE_API_PORT:-13000}"
WEB_UI_PORT="${WEB_UI_PORT:-12088}"
VM_MEMORY_MB="${VM_MEMORY_MB:-6144}"
VM_CPUS="${VM_CPUS:-4}"
QEMU_PIDFILE="${QEMU_PIDFILE:-${WORK_DIR}/qemu.pid}"
QEMU_SERIAL_LOG="${QEMU_SERIAL_LOG:-${WORK_DIR}/qemu-serial.log}"
OVMF="${OVMF:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
USE_TCG="${USE_TCG:-auto}"

[[ -f "${IMAGE}" ]] || { echo "missing image ${IMAGE}" >&2; exit 1; }
[[ -f "${OVMF}" ]] || { echo "install ovmf" >&2; exit 1; }

pick_accel() {
  if [[ "${USE_TCG}" == "1" ]]; then echo tcg; return; fi
  if [[ "${USE_TCG}" == "0" ]] && [[ -e /dev/kvm ]]; then echo kvm; return; fi
  if [[ -e /dev/kvm ]]; then
    sudo chmod 666 /dev/kvm 2>/dev/null || true
    if timeout 3 qemu-system-x86_64 -enable-kvm -machine q35 -accel kvm -cpu host -m 64 -display none -serial none 2>/dev/null; then
      echo kvm; return
    fi
  fi
  echo tcg
}

ACCEL="$(pick_accel)"
echo "[run-dev-vm] accel=${ACCEL} (KVM preferred; TCG fallback for nested broken hosts)"

pkill -9 -f 'qemu-system-x86.*opencloudos9-cubesandbox' 2>/dev/null || true
sleep 1
rm -f "${QEMU_PIDFILE}"
: > "${QEMU_SERIAL_LOG}"

QEMU_EXTRA=()
if [[ "${ACCEL}" == kvm ]]; then
  QEMU_EXTRA=(-enable-kvm -cpu host)
else
  QEMU_EXTRA=(-accel tcg -cpu max)
fi

qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" "${QEMU_EXTRA[@]}" \
  -m "${VM_MEMORY_MB}" -smp "${VM_CPUS}" \
  -name opencloudos9-cubesandbox \
  -drive if=pflash,format=raw,readonly=on,file="${OVMF}" \
  -drive if=virtio,file="${IMAGE}",format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::"${SSH_PORT}"-:22,hostfwd=tcp::"${CUBE_API_PORT}"-:3000,hostfwd=tcp::11080-:80,hostfwd=tcp::11443-:443,hostfwd=tcp::"${WEB_UI_PORT}"-:12088 \
  -device virtio-net,netdev=net0 \
  -daemonize -pidfile "${QEMU_PIDFILE}" \
  -display none -serial "file:${QEMU_SERIAL_LOG}"
