#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Load ashmem_linux for OpenCloudOS 9 (kernel 6.6) when ReDroid needs /dev/ashmem.
set -euo pipefail
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" 'sudo bash -s' <<'GUEST'
set -euo pipefail
grep -q ashmem /proc/misc && { echo "[ashmem] already loaded"; exit 0; }
if [[ ! -d /tmp/redroid-modules/ashmem ]]; then
  yum install -y git kmod make gcc "kernel-devel-$(uname -r)" elfutils-libelf-devel unzip
  cd /tmp && rm -rf redroid-modules
  git clone --depth 1 https://github.com/remote-android/redroid-modules.git
  cd redroid-modules/ashmem
  sed -i 's/vma->vm_flags &= ~calc_vm_may_flags(~asma->prot_mask);/vm_flags_clear(vma, calc_vm_may_flags(~asma->prot_mask));/' ashmem.c
  sed -i '/register_shrinker/d;/unregister_shrinker/d' ashmem.c
  make && make install
fi
insmod /tmp/redroid-modules/ashmem/ashmem_linux.ko 2>/dev/null || modprobe ashmem_linux
grep ashmem /proc/misc
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder /dev/ashmem 2>/dev/null || true
GUEST

echo "[ashmem] guest ashmem ready"
