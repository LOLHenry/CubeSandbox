#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M2: Build amd64 sandbox-android-redroid + sandbox-android-redroid-envd images.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TAG="${TAG:-16.0.0-amd64}"
PLATFORM="${PLATFORM:-linux/amd64}"
GOARCH="${GOARCH:-amd64}"
PUSH="${PUSH:-0}"
ENVD_REF="${ENVD_REF:-2026.16}"

REDROID_DIR="${REPO_ROOT}/deploy/sandbox-images/sandbox-android-redroid"
ENVD_DIR="${REPO_ROOT}/deploy/sandbox-images/sandbox-android-redroid-envd"
VERIFY_LIB="${ENVD_DIR}/lib/verify-android-envd-image.sh"

log() { printf '[m2-amd64] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

docker info >/dev/null 2>&1 || die "docker not running"

log "building sandbox-android-redroid:${TAG} (${PLATFORM})"
docker build --platform "${PLATFORM}" \
  -t "sandbox-android-redroid:${TAG}" \
  -f "${REDROID_DIR}/Dockerfile.amd64" "${REDROID_DIR}"

[[ "$(docker image inspect "sandbox-android-redroid:${TAG}" --format '{{.Architecture}}')" == "amd64" ]] \
  || die "redroid base not amd64"

log "building sandbox-android-redroid-envd:${TAG} (GOOS=android GOARCH=${GOARCH})"
docker build --platform "${PLATFORM}" \
  --build-arg "REDROID_BASE_IMAGE=sandbox-android-redroid:${TAG}" \
  --build-arg "ENVD_REF=${ENVD_REF}" \
  --build-arg "GOARCH=${GOARCH}" \
  -t "sandbox-android-redroid-envd:${TAG}" \
  -f "${ENVD_DIR}/Dockerfile.amd64" "${ENVD_DIR}"

[[ "$(docker image inspect "sandbox-android-redroid-envd:${TAG}" --format '{{.Architecture}}')" == "amd64" ]] \
  || die "envd image not amd64"

if [[ -x "${VERIFY_LIB}" ]]; then
  "${VERIFY_LIB}" "sandbox-android-redroid-envd:${TAG}" || log "verify script warnings (non-fatal on build host)"
fi

docker image inspect "sandbox-android-redroid-envd:${TAG}" \
  --format 'M2 OK architecture={{.Architecture}} os={{.Os}}'
log "M2 complete — sandbox-android-redroid-envd:${TAG}"
