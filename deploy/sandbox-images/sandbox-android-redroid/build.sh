#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Build and optionally push the CubeSandbox Android (ReDroid AOSP 16) image for Kunpeng ARM64.
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid/build.sh
#   PUSH=1 ./deploy/sandbox-images/sandbox-android-redroid/build.sh
#   TAG=16.0.0-arm64 PUSH=1 REGISTRY=cube-sandbox-int.tencentcloudcr.com/cube-sandbox ./build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${TAG:-16.0.0-arm64}"
REGISTRY="${REGISTRY:-cube-sandbox-cn.tencentcloudcr.com/cube-sandbox}"
IMAGE_NAME="${REGISTRY}/sandbox-android-redroid:${TAG}"
PLATFORM="${PLATFORM:-linux/arm64}"
PUSH="${PUSH:-0}"

echo "Building ${IMAGE_NAME} (${PLATFORM})"
docker build --platform "${PLATFORM}" -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# Mirror tag for int registry when building cn default.
if [[ "${REGISTRY}" == *"-cn."* ]]; then
  INT_IMAGE="cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:${TAG}"
  docker tag "${IMAGE_NAME}" "${INT_IMAGE}"
  echo "Tagged ${INT_IMAGE}"
fi

LOCAL_TAG="sandbox-android-redroid:${TAG}"
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
