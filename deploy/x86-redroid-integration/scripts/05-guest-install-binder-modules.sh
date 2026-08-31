#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install ReDroid binder/ashmem kernel modules inside dev-env guest (M1 prereq).
set -euo pipefail
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" 'sudo bash -s' <<'GUEST'
set -euo pipefail
grep -q binder /proc/filesystems && { echo "[binder] already present"; exit 0; }
yum install -y git kmod make gcc "kernel-devel-$(uname -r)" elfutils-libelf-devel
cd /tmp
rm -rf redroid-modules
git clone --depth 1 https://github.com/remote-android/redroid-modules.git
cd redroid-modules
make
make install
modprobe binder_linux devices="binder,hwbinder,vndbinder"
modprobe ashmem_linux 2>/dev/null || true
grep binder /proc/filesystems
lsmod | grep -E 'binder|ashmem'
GUEST

echo "[binder] guest modules ready"
