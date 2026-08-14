#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Build CubeSandbox Android (ReDroid + envd) image for Kunpeng ARM64.
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh
#   PUSH=1 ./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh
#   TAG=16.0.0-arm64 PUSH=1 REGISTRY=cube-sandbox-int.tencentcloudcr.com/cube-sandbox ./build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDROID_DIR="$(cd "${SCRIPT_DIR}/../sandbox-android-redroid" && pwd)"
TAG="${TAG:-16.0.0-arm64}"
REGISTRY="${REGISTRY:-cube-sandbox-cn.tencentcloudcr.com/cube-sandbox}"
IMAGE_NAME="${REGISTRY}/sandbox-android-redroid-envd:${TAG}"
REDROID_LOCAL="sandbox-android-redroid:${TAG}"
PLATFORM="${PLATFORM:-linux/arm64}"
PUSH="${PUSH:-0}"
ENVD_BASE_IMAGE="${ENVD_BASE_IMAGE:-ghcr.io/tencentcloud/cubesandbox-base:2026.16}"
ENVD_FALLBACK_IMAGE="${ENVD_FALLBACK_IMAGE:-cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest}"

if ! docker image inspect "${REDROID_LOCAL}" >/dev/null 2>&1; then
  echo "Base image ${REDROID_LOCAL} not found; building via ${REDROID_DIR}/build.sh"
  TAG="${TAG}" "${REDROID_DIR}/build.sh"
fi

pull_envd_source() {
  local image="$1"
  echo "Pulling envd source image ${image}"
  if docker pull --platform "${PLATFORM}" "${image}"; then
    ENVD_BASE_IMAGE="${image}"
    return 0
  fi
  return 1
}

if ! pull_envd_source "${ENVD_BASE_IMAGE}"; then
  echo "WARN: ${ENVD_BASE_IMAGE} unavailable for ${PLATFORM}; trying ${ENVD_FALLBACK_IMAGE}"
  pull_envd_source "${ENVD_FALLBACK_IMAGE}"
fi

echo "Building ${IMAGE_NAME} (${PLATFORM}) with envd from ${ENVD_BASE_IMAGE}"
docker build --platform "${PLATFORM}" \
  --build-arg "REDROID_BASE_IMAGE=${REDROID_LOCAL}" \
  --build-arg "ENVD_BASE_IMAGE=${ENVD_BASE_IMAGE}" \
  -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

if [[ "${REGISTRY}" == *"-cn."* ]]; then
  INT_IMAGE="cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-envd:${TAG}"
  docker tag "${IMAGE_NAME}" "${INT_IMAGE}"
  echo "Tagged ${INT_IMAGE}"
fi

LOCAL_TAG="sandbox-android-redroid-envd:${TAG}"
docker tag "${IMAGE_NAME}" "${LOCAL_TAG}"
echo "Tagged ${LOCAL_TAG}"

if [[ "${PUSH}" == "1" ]]; then
  docker push "${IMAGE_NAME}"
  if [[ "${REGISTRY}" == *"-cn."* ]]; then
    docker push "${INT_IMAGE}"
  fi
  echo "Pushed ${IMAGE_NAME}"
fi

docker image inspect "${IMAGE_NAME}" --format 'architecture={{.Architecture}} os={{.Os}}'
