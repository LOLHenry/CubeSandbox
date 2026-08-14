#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Verify sandbox-android-redroid-envd image: android/bionic envd binary + :49983/health.
# Run on Kunpeng (aarch64) before tpl create-from-image.
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-envd/verify-envd-health.sh
#   IMAGE=sandbox-android-redroid-envd:16.0.0-arm64 TIMEOUT=90 ./verify-envd-health.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-sandbox-android-redroid-envd:16.0.0-arm64}"
CONTAINER="${CONTAINER:-redroid-envd-verify}"
TIMEOUT="${TIMEOUT:-90}"
SKIP_HEALTH="${SKIP_HEALTH:-0}"

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
  echo "SKIP_HEALTH=1: skipping privileged container /health smoke test"
  exit 0
fi

echo "==> Starting ReDroid + envd (privileged, same as template build)"
docker run -d --privileged --name "${CONTAINER}" "${IMAGE}" >/dev/null

echo "==> Waiting for envd GET /health => 204 (timeout ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
ok=""
while (( SECONDS < deadline )); do
  if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "ERROR: container exited early" >&2
    docker logs "${CONTAINER}" 2>&1 | tail -30 >&2 || true
    docker exec "${CONTAINER}" cat /data/local/tmp/envd.log 2>/dev/null | tail -20 >&2 || true
    exit 1
  fi
  code="$(docker exec "${CONTAINER}" toybox wget -q -S -O /dev/null http://127.0.0.1:49983/health 2>&1 | awk '/HTTP\// {print $2; exit}')" || true
  if [[ "${code}" == "204" ]]; then
    ok=1
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

if [[ -z "${ok}" ]]; then
  echo "ERROR: envd /health never returned 204 within ${TIMEOUT}s" >&2
  docker exec "${CONTAINER}" cat /data/local/tmp/envd.log 2>/dev/null | tail -30 >&2 || true
  exit 1
fi

echo "OK: envd /health => 204"
echo ""
echo "Next: cubemastercli tpl create-from-image \\"
echo "  --image ${IMAGE} \\"
echo "  --writable-layer-size 10Gi \\"
echo "  --expose-port 5555 \\"
echo "  --probe 49983 --probe-path /health \\"
echo "  --cpu 4000 --memory 6144"
