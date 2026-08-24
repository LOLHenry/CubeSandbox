#!/usr/bin/env bash
# Build sandbox-android-redroid-envd Docker image fully offline.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-envd:16.0.0-arm64}"
# Default: host Go compile + inject (no docker.io pull, no BuildKit syntax frontend).
BUILD_MODE="${BUILD_MODE:-inject}"
REDROID_TAR="$(ls "${KIT_ROOT}"/images/redroid-*-docker.tar.gz 2>/dev/null | head -1)"

command -v docker >/dev/null || { echo "docker required" >&2; exit 1; }

if [[ -n "${REDROID_TAR}" ]]; then
  if ! docker image inspect redroid:16.0.0_64only-latest >/dev/null 2>&1; then
    echo "==> Loading ReDroid base from $(basename "${REDROID_TAR}")"
    gunzip -c "${REDROID_TAR}" | docker load
  fi
else
  echo "WARN: no redroid image tarball in kit; ensure redroid:16.0.0_64only-latest is loaded" >&2
fi

docker image inspect redroid:16.0.0_64only-latest --format 'redroid arch={{.Architecture}}' \
  || { echo "ERROR: load ReDroid base first" >&2; exit 1; }

build_inject() {
  echo "==> BUILD_MODE=inject: compile with host Go, copy into ReDroid (fully offline)"
  "${KIT_ROOT}/scripts/02-build-binaries.sh"
  # Legacy builder avoids BuildKit pulling docker/dockerfile frontend from registry.
  DOCKER_BUILDKIT=0 docker build -f "${KIT_ROOT}/Dockerfile.inject" -t "${IMAGE_TAG}" "${KIT_ROOT}"
}

build_offline_dockerfile() {
  GOLANG_TAR="$(ls "${KIT_ROOT}"/images/golang-*-bookworm-arm64-docker.tar.gz 2>/dev/null | head -1)"
  if [[ -n "${GOLANG_TAR}" ]] && ! docker image inspect golang:1.25.4-bookworm >/dev/null 2>&1; then
    echo "==> Loading golang builder from $(basename "${GOLANG_TAR}")"
    gunzip -c "${GOLANG_TAR}" | docker load
  fi
  if ! docker image inspect golang:1.25.4-bookworm >/dev/null 2>&1; then
    echo "ERROR: golang:1.25.4-bookworm not loaded; use BUILD_MODE=inject (default)" >&2
    exit 1
  fi
  echo "==> BUILD_MODE=offline: multi-stage build with local golang image"
  DOCKER_BUILDKIT=0 docker build -f "${KIT_ROOT}/Dockerfile.offline" -t "${IMAGE_TAG}" "${KIT_ROOT}"
}

case "${BUILD_MODE}" in
  inject) build_inject ;;
  offline) build_offline_dockerfile ;;
  *)
    echo "ERROR: BUILD_MODE must be inject or offline (got: ${BUILD_MODE})" >&2
    exit 1
    ;;
esac

docker image inspect "${IMAGE_TAG}" --format 'image={{.Id}} arch={{.Architecture}} entrypoint={{json .Config.Entrypoint}}'
echo "OK: ${IMAGE_TAG}"
