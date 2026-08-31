#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M1: Standalone ReDroid on x86 (docker + adb).
set -euo pipefail
REDROID_IMAGE="${REDROID_IMAGE:-redroid/redroid:16.0.0_64only-latest}"
CONTAINER="${CONTAINER:-redroid-x86-verify}"
ADB_PORT="${ADB_PORT:-5555}"
TIMEOUT="${TIMEOUT:-180}"
log() { printf '[m1-redroid] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }
command -v docker >/dev/null || die "missing docker"
command -v adb >/dev/null || die "missing adb"
# Built-in binder (CONFIG_ANDROID_BINDER_IPC=y) uses /dev/binder*; module path uses /proc/filesystems
if [[ ! -e /dev/binder ]]; then
  grep -q binder /proc/filesystems || die "binder missing — use dev-env VM or modprobe binder_linux"
  if command -v modprobe >/dev/null 2>&1; then
    modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>/dev/null || true
  fi
fi
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder 2>/dev/null || sudo chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder 2>/dev/null || true
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
log "pull ${REDROID_IMAGE}"
docker pull --platform linux/amd64 "${REDROID_IMAGE}"
[[ "$(docker image inspect "${REDROID_IMAGE}" --format '{{.Architecture}}')" == "amd64" ]] || die "not amd64"
docker run -d --privileged --name "${CONTAINER}" -p "${ADB_PORT}:5555" "${REDROID_IMAGE}" \
  androidboot.redroid_width=1080 androidboot.redroid_height=1920 \
  androidboot.redroid_dpi=480 androidboot.redroid_gpu_mode=guest
adb start-server >/dev/null 2>&1 || true
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  adb connect "127.0.0.1:${ADB_PORT}" 2>/dev/null | grep -q connected || { sleep 5; continue; }
  adb -s "127.0.0.1:${ADB_PORT}" shell getprop sys.boot_completed 2>/dev/null | grep -q 1 || { sleep 5; continue; }
  log "gralloc=$(adb -s 127.0.0.1:${ADB_PORT} shell getprop ro.hardware.gralloc)"
  adb -s "127.0.0.1:${ADB_PORT}" shell getprop ro.build.version.release
  exit 0
done
die "timeout — docker logs ${CONTAINER}"
