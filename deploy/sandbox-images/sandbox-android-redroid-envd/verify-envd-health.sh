#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Verify sandbox-android-redroid-envd image:
#   - Android/bionic envd ELF
#   - envd GET :49983/health => 204
#   - adbd listening on :5555 after Android boot
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-envd/verify-envd-health.sh
#   IMAGE=sandbox-android-redroid-envd:16.0.0-arm64 TIMEOUT=180 ./verify-envd-health.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-sandbox-android-redroid-envd:16.0.0-arm64}"
CONTAINER="${CONTAINER:-redroid-envd-verify}"
ENVD_PORT="${ENVD_PORT:-49983}"
ADB_PORT="${ADB_PORT:-5555}"
TIMEOUT="${TIMEOUT:-180}"
ADB_TIMEOUT="${ADB_TIMEOUT:-${TIMEOUT}}"
SKIP_HEALTH="${SKIP_HEALTH:-0}"
SKIP_ADB="${SKIP_ADB:-0}"
PUBLISH_PORTS="${PUBLISH_PORTS:-1}"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: image not found: ${IMAGE}" >&2
  echo "Build: ./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh" >&2
  echo "Or load the envd offline bundle: gunzip -c cube-sandbox-android-kunpeng-arm64-envd-docker-*.tar.gz | docker load" >&2
  exit 1
fi

echo "==> Checking envd ELF (must be Android /system/bin/linker64, not GOOS=linux static)"
"${SCRIPT_DIR}/lib/verify-android-envd-image.sh" "${IMAGE}"

if [[ "${SKIP_HEALTH}" == "1" ]]; then
  echo "SKIP_HEALTH=1: skipping privileged container smoke test"
  exit 0
fi

publish_args=()
if [[ "${PUBLISH_PORTS}" == "1" ]]; then
  publish_args=(-p "${ENVD_PORT}:${ENVD_PORT}" -p "${ADB_PORT}:${ADB_PORT}")
fi

echo "==> Starting ReDroid + envd (privileged, same as template build)"
docker run -d --privileged --name "${CONTAINER}" "${publish_args[@]}" "${IMAGE}" >/dev/null

echo "==> Waiting for envd GET /health => 204 (timeout ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
envd_ok=""
while (( SECONDS < deadline )); do
  if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "ERROR: container exited early" >&2
    docker logs "${CONTAINER}" 2>&1 | tail -30 >&2 || true
    docker exec "${CONTAINER}" cat /data/local/tmp/envd.log 2>/dev/null | tail -20 >&2 || true
    exit 1
  fi
  code="$(docker exec "${CONTAINER}" toybox wget -q -S -O /dev/null "http://127.0.0.1:${ENVD_PORT}/health" 2>&1 | awk '/HTTP\// {print $2; exit}')" || true
  if [[ "${code}" == "204" ]]; then
    envd_ok=1
    break
  fi
  if docker exec "${CONTAINER}" ps -A 2>/dev/null | grep -q '[e]nvd'; then
    echo "  envd process up, health=${code:-pending} ..."
  else
    echo "  envd process missing, checking log ..."
    docker exec "${CONTAINER}" cat /data/local/tmp/envd.log 2>/dev/null | tail -5 || true
  fi
  sleep 3
done

if [[ -z "${envd_ok}" ]]; then
  echo "ERROR: envd /health never returned 204 within ${TIMEOUT}s" >&2
  docker exec "${CONTAINER}" cat /data/local/tmp/envd.log 2>/dev/null | tail -30 >&2 || true
  exit 1
fi

echo "OK: envd /health => 204"

if [[ "${PUBLISH_PORTS}" == "1" ]]; then
  host_envd_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${ENVD_PORT}/health" 2>/dev/null || true)"
  if [[ "${host_envd_code}" == "204" ]]; then
    echo "OK: host-published envd :${ENVD_PORT}/health => 204"
  else
    echo "WARN: host-published envd :${ENVD_PORT}/health => ${host_envd_code:-000} (in-container probe passed)" >&2
  fi
fi

if [[ "${SKIP_ADB}" == "1" ]]; then
  echo "SKIP_ADB=1: skipping adbd :${ADB_PORT} check"
else
  echo "==> Waiting for adbd on :${ADB_PORT} (timeout ${ADB_TIMEOUT}s; Android boot is slow)"
  adb_deadline=$((SECONDS + ADB_TIMEOUT))
  adb_ok=""
  while (( SECONDS < adb_deadline )); do
    if docker exec "${CONTAINER}" ss -lntp 2>/dev/null | grep -q ":${ADB_PORT} "; then
      adb_ok=1
      break
    fi
    if docker exec "${CONTAINER}" toybox netstat -lntp 2>/dev/null | grep -q ":${ADB_PORT} "; then
      adb_ok=1
      break
    fi
    boot="$(docker exec "${CONTAINER}" getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    echo "  boot_completed=${boot:-0}, adbd :${ADB_PORT} pending ..."
    sleep 5
  done

  if [[ -z "${adb_ok}" ]]; then
    echo "ERROR: adbd never listened on :${ADB_PORT} within ${ADB_TIMEOUT}s" >&2
    docker exec "${CONTAINER}" ss -lntp 2>/dev/null | head -20 >&2 || true
    exit 1
  fi
  echo "OK: adbd listening on :${ADB_PORT}"

  if [[ "${PUBLISH_PORTS}" == "1" ]] && command -v adb >/dev/null 2>&1; then
    adb kill-server >/dev/null 2>&1 || true
    if adb connect "127.0.0.1:${ADB_PORT}" 2>/dev/null | grep -qiE 'connected|already'; then
      if adb -s "127.0.0.1:${ADB_PORT}" shell getprop ro.hardware.gralloc 2>/dev/null | grep -q redroid; then
        echo "OK: adb connect 127.0.0.1:${ADB_PORT} (ro.hardware.gralloc=redroid)"
      else
        echo "OK: adb connect 127.0.0.1:${ADB_PORT}"
      fi
    else
      echo "WARN: adb connect 127.0.0.1:${ADB_PORT} failed (port publish may still work in CubeVM)" >&2
    fi
  fi
fi

echo ""
echo "Next: cubemastercli tpl create-from-image \\"
echo "  --image ${IMAGE} \\"
echo "  --writable-layer-size 10Gi \\"
echo "  --expose-port ${ADB_PORT} \\"
echo "  --expose-port ${ENVD_PORT} \\"
echo "  --probe ${ENVD_PORT} --probe-path /health \\"
echo "  --cpu 4000 --memory 6144"
echo ""
echo "External access: set network-agent --host-proxy-bind-ip=0.0.0.0, expose both ports above,"
echo "then use cubemastercli info for host_port mappings (adb connect / curl envd /health)."
