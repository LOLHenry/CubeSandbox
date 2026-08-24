#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Export upstream ReDroid base image for Kunpeng / offline install.
#
# Usage:
#   ./deploy/one-click/scripts/one-click/build-redroid-base-offline-bundle.sh
#   RELEASE_TAG=base-1 REDROID_TAG=16.0.0_64only-latest ./build-redroid-base-offline-bundle.sh
#
# Environment:
#   REDROID_TAG          Upstream tag (default: 16.0.0_64only-latest)
#   RELEASE_TAG          Filename suffix (default: redroid-16.0.0_64only-arm64)
#   PULL_IMAGE=1         docker pull before export (default: 1)
#   OUT_DIR              Output directory (default: deploy/one-click/dist)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONE_CLICK_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${ONE_CLICK_DIR}/lib/common.sh"

REDROID_TAG="${REDROID_TAG:-16.0.0_64only-latest}"
RELEASE_TAG="${RELEASE_TAG:-redroid-16.0.0_64only-arm64}"
UPSTREAM_IMAGE="redroid/redroid:${REDROID_TAG}"
LOCAL_IMAGE="redroid:${REDROID_TAG}"
OUT_DIR="${OUT_DIR:-${ONE_CLICK_DIR}/dist}"
PULL_IMAGE="${PULL_IMAGE:-1}"

BUNDLE_NAME="${BUNDLE_NAME:-${RELEASE_TAG}-docker.tar.gz}"
OUT_PATH="${OUT_DIR}/${BUNDLE_NAME}"
SHA_PATH="${OUT_PATH}.sha256"

require_cmd docker
mkdir -p "${OUT_DIR}"

if [[ "${PULL_IMAGE}" == "1" ]]; then
  log "pulling ${UPSTREAM_IMAGE} (linux/arm64)"
  docker pull --platform linux/arm64 "${UPSTREAM_IMAGE}"
fi

if ! docker image inspect "${UPSTREAM_IMAGE}" >/dev/null 2>&1; then
  die "missing image ${UPSTREAM_IMAGE}; set PULL_IMAGE=1 or load manually"
fi

docker tag "${UPSTREAM_IMAGE}" "${LOCAL_IMAGE}"

ARCH="$(docker image inspect "${UPSTREAM_IMAGE}" --format '{{.Architecture}}')"
if [[ "${ARCH}" != "arm64" ]]; then
  die "image ${UPSTREAM_IMAGE} architecture is ${ARCH}, expected arm64 for Kunpeng"
fi

log "exporting ${UPSTREAM_IMAGE} and ${LOCAL_IMAGE} to ${OUT_PATH}"
docker save "${UPSTREAM_IMAGE}" "${LOCAL_IMAGE}" | gzip -c > "${OUT_PATH}"

SHA="$(sha256sum "${OUT_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "${BUNDLE_NAME}" > "${SHA_PATH}"

log "offline redroid base bundle ready: ${OUT_PATH}"
log "sha256 file: ${SHA_PATH}"
log "sha256=${SHA}"
log "load on Kunpeng: gunzip -c ${BUNDLE_NAME} | docker load"
log "verify: docker image inspect redroid:${REDROID_TAG} --format '{{.Architecture}}'"
