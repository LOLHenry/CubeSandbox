#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_IMAGE="${LOCAL_IMAGE:-sandbox-android-redroid-cube:16.0.0-arm64}"
CN_IMAGE="cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-cube:16.0.0-arm64"
GIT_SHORT="$(cat "${SCRIPT_DIR}/BUILDINFO" 2>/dev/null | sed -n 's/^git_short=//p' || echo unknown)"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/dist}"
BUNDLE="${OUT_DIR}/sandbox-android-redroid-cube-docker-${GIT_SHORT}.tar.gz"

command -v docker >/dev/null || { echo "docker required" >&2; exit 1; }

if ! docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1; then
  echo "==> Image missing; running build-docker-image.sh"
  "${SCRIPT_DIR}/build-docker-image.sh"
fi

mkdir -p "${OUT_DIR}"
docker tag "${LOCAL_IMAGE}" "${CN_IMAGE}" 2>/dev/null || true

echo "==> Exporting ${LOCAL_IMAGE} ${CN_IMAGE}"
docker save "${LOCAL_IMAGE}" "${CN_IMAGE}" 2>/dev/null | gzip -c > "${BUNDLE}" || \
  docker save "${LOCAL_IMAGE}" | gzip -c > "${BUNDLE}"

sha256sum "${BUNDLE}" > "${BUNDLE}.sha256"
echo "OK: ${BUNDLE}"
cat "${BUNDLE}.sha256"
