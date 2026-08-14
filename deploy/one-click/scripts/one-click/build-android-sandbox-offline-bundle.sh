#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Export Android sandbox Docker images for Kunpeng / yellow-zone offline install.
#
# Usage:
#   ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
#   RELEASE_TAG=v0.6.0 BUILD_IMAGE=1 ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
#   OUT_DIR=/tmp/android-bundle ./deploy/one-click/scripts/one-click/build-android-sandbox-offline-bundle.sh
#
# Environment:
#   RELEASE_TAG / CUBE_VERSION  Version suffix for bundle filename (e.g. v0.6.0)
#   ANDROID_IMAGE_TAG           Image tag (default: 16.0.0-arm64)
#   BUILD_IMAGE=1               Run deploy/sandbox-images/sandbox-android-redroid/build.sh first
#   BUNDLE_NAME                 Override output tarball name
#   OUT_DIR                     Output directory (default: deploy/one-click/dist)
#
# Prerequisites:
#   - docker with arm64 build/load support
#   - sandbox-android-redroid:16.0.0-arm64 (or BUILD_IMAGE=1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONE_CLICK_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${ONE_CLICK_DIR}/../.." && pwd)"
SANDBOX_IMAGE_DIR="${REPO_ROOT}/deploy/sandbox-images/sandbox-android-redroid"
# shellcheck source=../../lib/common.sh
source "${ONE_CLICK_DIR}/lib/common.sh"

TAG="${ANDROID_IMAGE_TAG:-16.0.0-arm64}"
RELEASE_TAG="${RELEASE_TAG:-${CUBE_VERSION:-}}"
CN_IMAGE="cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:${TAG}"
INT_IMAGE="cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:${TAG}"
LOCAL_IMAGE="sandbox-android-redroid:${TAG}"
OUT_DIR="${OUT_DIR:-${ONE_CLICK_DIR}/dist}"

if [[ -n "${RELEASE_TAG}" ]]; then
  BUNDLE_NAME="${BUNDLE_NAME:-cube-sandbox-android-kunpeng-arm64-docker-${RELEASE_TAG}.tar.gz}"
else
  BUNDLE_NAME="${BUNDLE_NAME:-cube-sandbox-android-kunpeng-arm64-docker.tar.gz}"
fi
OUT_PATH="${OUT_DIR}/${BUNDLE_NAME}"
SHA_PATH="${OUT_PATH}.sha256"

require_cmd docker
mkdir -p "${OUT_DIR}"

if [[ "${BUILD_IMAGE:-0}" == "1" ]]; then
  log "building android sandbox image (BUILD_IMAGE=1)"
  TAG="${TAG}" "${SANDBOX_IMAGE_DIR}/build.sh"
fi

ensure_image_tag() {
  local src="$1"
  local dst="$2"
  if docker image inspect "${dst}" >/dev/null 2>&1; then
    return 0
  fi
  docker tag "${src}" "${dst}"
  log "tagged ${dst} from ${src}"
}

SOURCE_IMAGE=""
for candidate in "${LOCAL_IMAGE}" "${CN_IMAGE}" "${INT_IMAGE}"; do
  if docker image inspect "${candidate}" >/dev/null 2>&1; then
    SOURCE_IMAGE="${candidate}"
    break
  fi
done

if [[ -z "${SOURCE_IMAGE}" ]]; then
  die "missing android sandbox image; set BUILD_IMAGE=1 or run ${SANDBOX_IMAGE_DIR}/build.sh"
fi

ensure_image_tag "${SOURCE_IMAGE}" "${LOCAL_IMAGE}"
ensure_image_tag "${SOURCE_IMAGE}" "${CN_IMAGE}"
ensure_image_tag "${SOURCE_IMAGE}" "${INT_IMAGE}"

ARCH="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
if [[ "${ARCH}" != "arm64" ]]; then
  die "image ${LOCAL_IMAGE} architecture is ${ARCH}, expected arm64 for Kunpeng bundle"
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

log "exporting ${LOCAL_IMAGE}, ${CN_IMAGE}, ${INT_IMAGE} to ${OUT_PATH}"
docker save "${LOCAL_IMAGE}" "${CN_IMAGE}" "${INT_IMAGE}" | gzip -c > "${OUT_PATH}"

SHA="$(sha256sum "${OUT_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "${BUNDLE_NAME}" > "${SHA_PATH}"

log "offline bundle ready: ${OUT_PATH}"
log "sha256 file: ${SHA_PATH}"
log "sha256=${SHA}"
log "load on target: gunzip -c ${BUNDLE_NAME} | docker load"
