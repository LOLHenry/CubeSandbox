#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Build ReDroid + fd-sanitize-starter image for Kunpeng ARM64 CubeVM cold-start tests.
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-cube/build.sh
#   TAG=16.0.0-arm64 ./deploy/sandbox-images/sandbox-android-redroid-cube/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDROID_DIR="$(cd "${SCRIPT_DIR}/../sandbox-android-redroid" && pwd)"
TAG="${TAG:-16.0.0-arm64}"
REGISTRY="${REGISTRY:-cube-sandbox-cn.tencentcloudcr.com/cube-sandbox}"
IMAGE_NAME="${REGISTRY}/sandbox-android-redroid-cube:${TAG}"
REDROID_LOCAL="sandbox-android-redroid:${TAG}"
LOCAL_TAG="sandbox-android-redroid-cube:${TAG}"
PLATFORM="${PLATFORM:-linux/arm64}"
PUSH="${PUSH:-0}"
GO_VERSION="${GO_VERSION:-1.25.4}"
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"

if ! docker image inspect "${REDROID_LOCAL}" >/dev/null 2>&1; then
  echo "Base image ${REDROID_LOCAL} not found; building via ${REDROID_DIR}/build.sh"
  TAG="${TAG}" "${REDROID_DIR}/build.sh"
fi

echo "Building ${IMAGE_NAME} (${PLATFORM})"
docker build --platform "${PLATFORM}" \
  --build-arg "REDROID_BASE_IMAGE=${REDROID_LOCAL}" \
  --build-arg "GO_VERSION=${GO_VERSION}" \
  -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

if [[ "${REGISTRY}" == *"-cn."* ]]; then
  INT_IMAGE="cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-cube:${TAG}"
  docker tag "${IMAGE_NAME}" "${INT_IMAGE}"
  echo "Tagged ${INT_IMAGE}"
fi

docker tag "${IMAGE_NAME}" "${LOCAL_TAG}"
echo "Tagged ${LOCAL_TAG}"

arch="$(docker image inspect "${IMAGE_NAME}" --format '{{.Architecture}}')"
if [[ "${arch}" != "arm64" ]]; then
  echo "ERROR: expected arm64, got ${arch}" >&2
  exit 1
fi

entrypoint="$(docker image inspect "${IMAGE_NAME}" --format '{{json .Config.Entrypoint}}')"
if [[ "${entrypoint}" != '["/usr/bin/fd-sanitize-starter"]' ]]; then
  echo "ERROR: unexpected Entrypoint ${entrypoint}" >&2
  exit 1
fi

echo "OK: ${LOCAL_TAG} entrypoint=${entrypoint} arch=${arch}"

if [[ "${PUSH}" == "1" ]]; then
  docker push "${IMAGE_NAME}"
  if [[ "${REGISTRY}" == *"-cn."* ]]; then
    docker push "${INT_IMAGE}"
  fi
  echo "Pushed ${IMAGE_NAME}"
fi
