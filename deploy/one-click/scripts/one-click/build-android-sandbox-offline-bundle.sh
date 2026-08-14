#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Export Android sandbox Docker images for Kunpeng / yellow-zone offline install.
#
# Usage:
#   ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
#   OUT_DIR=/tmp/android-bundle ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
#
# Prerequisites:
#   - docker with arm64 images loaded locally
#   - sandbox-android-redroid:16.0.0-arm64 (see deploy/sandbox-images/sandbox-android-redroid/build.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONE_CLICK_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${ONE_CLICK_DIR}/lib/common.sh"

TAG="${ANDROID_IMAGE_TAG:-16.0.0-arm64}"
CN_IMAGE="cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:${TAG}"
LOCAL_IMAGE="sandbox-android-redroid:${TAG}"
OUT_DIR="${OUT_DIR:-${ONE_CLICK_DIR}/dist}"
BUNDLE_NAME="${BUNDLE_NAME:-cube-sandbox-android-kunpeng-arm64-docker.tar.gz}"
OUT_PATH="${OUT_DIR}/${BUNDLE_NAME}"

require_cmd docker
mkdir -p "${OUT_DIR}"

if ! docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1; then
  if docker image inspect "${CN_IMAGE}" >/dev/null 2>&1; then
    docker tag "${CN_IMAGE}" "${LOCAL_IMAGE}"
  else
    die "missing local image ${LOCAL_IMAGE}; run deploy/sandbox-images/sandbox-android-redroid/build.sh first"
  fi
fi

ARCH="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
if [[ "${ARCH}" != "arm64" ]]; then
  die "image ${LOCAL_IMAGE} architecture is ${ARCH}, expected arm64 for Kunpeng bundle"
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

log "exporting ${LOCAL_IMAGE} and ${CN_IMAGE} to ${OUT_PATH}"
docker save "${LOCAL_IMAGE}" "${CN_IMAGE}" | gzip -c > "${OUT_PATH}"

SHA="$(sha256sum "${OUT_PATH}" | awk '{print $1}')"
log "offline bundle ready: ${OUT_PATH}"
log "sha256=${SHA}"
log "load on target: gunzip -c ${BUNDLE_NAME} | docker load"
