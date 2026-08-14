#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Build CubeSandbox Android (ReDroid + envd) image for Kunpeng ARM64.
# envd is compiled with GOOS=android inside the Dockerfile (not copied from
# cubesandbox-base, which ships a GOOS=linux binary incompatible with ReDroid).
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh
#   PUSH=1 ./deploy/sandbox-images/sandbox-android-redroid-envd/build.sh
#   TAG=16.0.0-arm64 PUSH=1 REGISTRY=cube-sandbox-int.tencentcloudcr.com/cube-sandbox ./build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_LIB="${SCRIPT_DIR}/lib/verify-android-envd-image.sh"
REDROID_DIR="$(cd "${SCRIPT_DIR}/../sandbox-android-redroid" && pwd)"
TAG="${TAG:-16.0.0-arm64}"
REGISTRY="${REGISTRY:-cube-sandbox-cn.tencentcloudcr.com/cube-sandbox}"
IMAGE_NAME="${REGISTRY}/sandbox-android-redroid-envd:${TAG}"
REDROID_LOCAL="sandbox-android-redroid:${TAG}"
PLATFORM="${PLATFORM:-linux/arm64}"
PUSH="${PUSH:-0}"
ENVD_REF="${ENVD_REF:-2026.16}"
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"

if ! docker image inspect "${REDROID_LOCAL}" >/dev/null 2>&1; then
  echo "Base image ${REDROID_LOCAL} not found; building via ${REDROID_DIR}/build.sh"
  TAG="${TAG}" "${REDROID_DIR}/build.sh"
fi

echo "Building ${IMAGE_NAME} (${PLATFORM}) with envd GOOS=android ENVD_REF=${ENVD_REF}"
docker build --platform "${PLATFORM}" \
  --build-arg "REDROID_BASE_IMAGE=${REDROID_LOCAL}" \
  --build-arg "ENVD_REF=${ENVD_REF}" \
  -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

"${VERIFY_LIB}" "${IMAGE_NAME}"

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
