#!/usr/bin/env bash
# Build sandbox-android-redroid-envd Docker image fully offline.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-envd:16.0.0-arm64}"
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

GOLANG_TAR="$(ls "${KIT_ROOT}"/images/golang-*-bookworm-arm64-docker.tar.gz 2>/dev/null | head -1)"
if [[ -n "${GOLANG_TAR}" ]] && ! docker image inspect golang:1.25.4-bookworm >/dev/null 2>&1; then
  echo "==> Loading golang builder from $(basename "${GOLANG_TAR}")"
  gunzip -c "${GOLANG_TAR}" | docker load
fi

docker image inspect redroid:16.0.0_64only-latest --format 'redroid arch={{.Architecture}}' \
  || { echo "ERROR: load ReDroid base first" >&2; exit 1; }

# Prefer golang image from host; fallback to local go in Dockerfile via multi-stage with COPY only
if ! docker image inspect golang:1.25.4-bookworm >/dev/null 2>&1; then
  echo "==> golang:1.25.4-bookworm not found; building with host Go via 02-build-binaries.sh path"
  "${KIT_ROOT}/scripts/02-build-binaries.sh"
  cat > "${KIT_ROOT}/Dockerfile.inject" <<'DOCKERFILE'
ARG REDROID_BASE_IMAGE=redroid:16.0.0_64only-latest
FROM ${REDROID_BASE_IMAGE}
COPY out/envd /usr/bin/envd
COPY out/envd-starter /usr/bin/envd-starter
COPY src/android-init/cube-envd.rc /vendor/etc/init/cube-envd.rc
COPY src/android-init/cube-envd.rc /system/etc/init/cube-envd.rc
COPY src/start-cube-envd.sh /usr/bin/start-cube-envd.sh
ENV ENVD_PORT=49983
EXPOSE 49983 5555
CMD ["androidboot.redroid_width=1080", "androidboot.redroid_height=1920", "androidboot.redroid_dpi=480", "androidboot.redroid_gpu_mode=guest"]
ENTRYPOINT ["/usr/bin/envd-starter"]
DOCKERFILE
  docker build -f "${KIT_ROOT}/Dockerfile.inject" -t "${IMAGE_TAG}" "${KIT_ROOT}"
else
  echo "==> Building with Dockerfile.offline (golang builder image present)"
  docker build -f "${KIT_ROOT}/Dockerfile.offline" -t "${IMAGE_TAG}" "${KIT_ROOT}"
fi

docker image inspect "${IMAGE_TAG}" --format 'image={{.Id}} arch={{.Architecture}} entrypoint={{json .Config.Entrypoint}}'
echo "OK: ${IMAGE_TAG}"
