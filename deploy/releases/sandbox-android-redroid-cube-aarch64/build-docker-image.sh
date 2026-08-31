#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-cube:16.0.0-arm64}"
REDROID_BASE="${REDROID_BASE_IMAGE:-redroid:16.0.0_64only-latest}"

command -v docker >/dev/null || { echo "docker required" >&2; exit 1; }

if ! docker image inspect "${REDROID_BASE}" >/dev/null 2>&1; then
  ALT="sandbox-android-redroid:16.0.0-arm64"
  if docker image inspect "${ALT}" >/dev/null 2>&1; then
    REDROID_BASE="${ALT}"
  else
    echo "ERROR: load ${REDROID_BASE} or ${ALT} first" >&2
    exit 1
  fi
fi

ARCH="$(docker image inspect "${REDROID_BASE}" --format '{{.Architecture}}')"
if [[ "${ARCH}" != "arm64" ]]; then
  echo "ERROR: base ${REDROID_BASE} is ${ARCH}, need arm64" >&2
  exit 1
fi

if [[ ! -x "${SCRIPT_DIR}/bin/fd-sanitize-starter" ]]; then
  echo "ERROR: missing ${SCRIPT_DIR}/bin/fd-sanitize-starter" >&2
  exit 1
fi

echo "==> Building ${IMAGE_TAG} from ${REDROID_BASE}"
DOCKER_BUILDKIT=0 docker build \
  -f "${SCRIPT_DIR}/Dockerfile.inject" \
  --build-arg "REDROID_BASE_IMAGE=${REDROID_BASE}" \
  -t "${IMAGE_TAG}" \
  "${SCRIPT_DIR}"

docker tag "${IMAGE_TAG}" "cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-cube:16.0.0-arm64" 2>/dev/null || true
docker tag "${IMAGE_TAG}" "sandbox-android-redroid-cube:16.0.0-arm64"

docker image inspect "${IMAGE_TAG}" --format 'OK image={{.Id}} arch={{.Architecture}} entrypoint={{json .Config.Entrypoint}}'
echo "Tagged: sandbox-android-redroid-cube:16.0.0-arm64"
