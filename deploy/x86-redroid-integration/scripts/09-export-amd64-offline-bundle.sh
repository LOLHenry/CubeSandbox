#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Export sandbox-android-redroid-envd amd64 Docker image for offline load on x86 hosts.
#
# Usage:
#   bash deploy/x86-redroid-integration/scripts/09-export-amd64-offline-bundle.sh
#   RELEASE_TAG=m2-preview BUILD_IMAGE=1 bash deploy/.../09-export-amd64-offline-bundle.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TAG="${ANDROID_IMAGE_TAG:-16.0.0-amd64}"
RELEASE_TAG="${RELEASE_TAG:-m2-preview}"
LOCAL_IMAGE="sandbox-android-redroid-envd:${TAG}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/deploy/x86-redroid-integration/dist}"
BUNDLE_NAME="${BUNDLE_NAME:-cube-sandbox-android-x86-amd64-envd-docker-${RELEASE_TAG}.tar.gz}"
OUT_PATH="${OUT_DIR}/${BUNDLE_NAME}"
SHA_PATH="${OUT_PATH}.sha256"

log() { printf '[x86-bundle] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

mkdir -p "${OUT_DIR}"

if [[ "${BUILD_IMAGE:-0}" == "1" ]]; then
  log "building image first"
  "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/07-build-amd64-redroid-envd.sh"
fi

docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1 || die "missing ${LOCAL_IMAGE}; run 07-build-amd64-redroid-envd.sh first"

ARCH="$(docker image inspect "${LOCAL_IMAGE}" --format '{{.Architecture}}')"
[[ "${ARCH}" == "amd64" ]] || die "expected amd64, got ${ARCH}"

log "exporting ${LOCAL_IMAGE} → ${OUT_PATH}"
docker save "${LOCAL_IMAGE}" | gzip -c > "${OUT_PATH}"

SHA="$(sha256sum "${OUT_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "${BUNDLE_NAME}" > "${SHA_PATH}"

log "bundle ready: ${OUT_PATH} ($(du -h "${OUT_PATH}" | awk '{print $1}'))"
log "sha256=${SHA}"
log "load: gunzip -c ${BUNDLE_NAME} | docker load"
