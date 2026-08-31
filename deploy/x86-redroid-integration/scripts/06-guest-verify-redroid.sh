#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M1: Run ReDroid + adb verification inside dev-env guest (via SSH).
set -euo pipefail
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"
ADB_PORT="${ADB_PORT:-5555}"
REDROID_IMAGE="${REDROID_IMAGE:-redroid/redroid:16.0.0_64only-latest}"
# TCG guests are slow; ReDroid init may need many minutes if it boots at all.
TIMEOUT="${TIMEOUT:-900}"

log() { printf '[m1-guest] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" \
  "REDROID_IMAGE=${REDROID_IMAGE} ADB_PORT=${ADB_PORT} TIMEOUT=${TIMEOUT} bash -s" <<'GUEST'
set -euo pipefail
REDROID_IMAGE="${REDROID_IMAGE:-redroid/redroid:16.0.0_64only-latest}"
CONTAINER="${CONTAINER:-redroid-x86-verify}"
ADB_PORT="${ADB_PORT:-5555}"
# TCG guests are slow; ReDroid init may need many minutes if it boots at all.
TIMEOUT="${TIMEOUT:-900}"
log() { printf '[m1-redroid] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

command -v docker >/dev/null || die "missing docker"
docker() { sudo docker "$@"; }
# Built-in binder (CONFIG_ANDROID_BINDER_IPC=y) exposes /dev/binder*, not /proc/filesystems
if [[ ! -e /dev/binder ]]; then
  grep -q binder /proc/filesystems || die "binder missing"
  modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>/dev/null || true
fi
sudo chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder 2>/dev/null || true

# ashmem required for Android property area on OpenCloudOS 6.6
if ! grep -q ashmem /proc/misc 2>/dev/null; then
  log "loading ashmem_linux module"
  if [[ ! -f /tmp/redroid-modules/ashmem/ashmem_linux.ko ]]; then
    yum install -y git kmod make gcc "kernel-devel-$(uname -r)" elfutils-libelf-devel >/dev/null
    cd /tmp && rm -rf redroid-modules
    git clone --depth 1 https://github.com/remote-android/redroid-modules.git
    cd redroid-modules/ashmem
    sed -i 's/vma->vm_flags &= ~calc_vm_may_flags(~asma->prot_mask);/vm_flags_clear(vma, calc_vm_may_flags(~asma->prot_mask));/' ashmem.c
    sed -i '/register_shrinker/d;/unregister_shrinker/d' ashmem.c
    make && sudo make install
  fi
  sudo insmod /tmp/redroid-modules/ashmem/ashmem_linux.ko 2>/dev/null || sudo modprobe ashmem_linux || true
fi
sudo chmod 666 /dev/ashmem 2>/dev/null || true

if ! command -v adb >/dev/null; then
  log "installing adb (platform-tools)"
  if ! command -v unzip >/dev/null; then
    sudo yum install -y unzip >/dev/null
  fi
  curl -fsSL -o /tmp/platform-tools.zip \
    https://dl.google.com/android/repository/platform-tools-latest-linux.zip
  sudo unzip -qo /tmp/platform-tools.zip -d /opt
  sudo ln -sf /opt/platform-tools/adb /usr/local/bin/adb
  rm -f /tmp/platform-tools.zip
fi

docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
sudo mkdir -p /tmp/redroid-data
log "pull ${REDROID_IMAGE}"
docker pull --platform linux/amd64 "${REDROID_IMAGE}"
[[ "$(docker image inspect "${REDROID_IMAGE}" --format '{{.Architecture}}')" == "amd64" ]] || die "not amd64"
docker run -d --privileged --name "${CONTAINER}" \
  --security-opt seccomp=unconfined \
  --device /dev/binder --device /dev/hwbinder --device /dev/vndbinder \
  --device /dev/ashmem \
  -v /tmp/redroid-data:/data \
  -p "${ADB_PORT}:5555" "${REDROID_IMAGE}" \
  androidboot.use_memfd=true androidboot.selinux=permissive \
  androidboot.redroid_width=1080 androidboot.redroid_height=1920 \
  androidboot.redroid_dpi=480 androidboot.redroid_gpu_mode=guest
adb start-server >/dev/null 2>&1 || true
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  adb connect "127.0.0.1:${ADB_PORT}" 2>/dev/null | grep -qi connected || { sleep 5; continue; }
  adb -s "127.0.0.1:${ADB_PORT}" shell getprop sys.boot_completed 2>/dev/null | grep -q 1 || { sleep 5; continue; }
  log "gralloc=$(adb -s 127.0.0.1:${ADB_PORT} shell getprop ro.hardware.gralloc)"
  adb -s "127.0.0.1:${ADB_PORT}" shell getprop ro.build.version.release
  exit 0
done
docker logs "${CONTAINER}" 2>&1 | tail -30
die "timeout"
GUEST

log "M1 OK — ReDroid booted in guest, adb connected"
