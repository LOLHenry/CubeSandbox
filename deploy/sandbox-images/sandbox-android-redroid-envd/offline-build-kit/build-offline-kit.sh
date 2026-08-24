#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Build a self-contained offline kit for compiling envd (GOOS=android) on Kunpeng.
# Run on a networked machine (or GHA arm64 runner); copy the output tarball to euler.
#
# Usage:
#   ./deploy/sandbox-images/sandbox-android-redroid-envd/offline-build-kit/build-offline-kit.sh
#   RELEASE_TAG=envd-offline-kit-1 INCLUDE_REDROID=1 ./build-offline-kit.sh
#
# Environment:
#   RELEASE_TAG       Bundle directory/tarball suffix (default: android-envd-offline-build-kit)
#   ENVD_REF          e2b-dev/infra tag (default: 2026.16)
#   GO_VERSION        Go toolchain version (default: 1.25.4)
#   INCLUDE_REDROID   Also docker pull+save redroid base (default: 1)
#   REDROID_TAG       redroid/redroid tag (default: 16.0.0_64only-latest)
#   OUT_DIR           Output parent dir (default: deploy/one-click/dist)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVD_IMAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ENVD_IMAGE_DIR}/../../.." && pwd)"
ONE_CLICK_DIR="${REPO_ROOT}/deploy/one-click"
# shellcheck source=../../../one-click/lib/common.sh
source "${ONE_CLICK_DIR}/lib/common.sh"

RELEASE_TAG="${RELEASE_TAG:-android-envd-offline-build-kit}"
ENVD_REF="${ENVD_REF:-2026.16}"
GO_VERSION="${GO_VERSION:-1.25.4}"
INCLUDE_REDROID="${INCLUDE_REDROID:-1}"
INCLUDE_GOLANG_IMAGE="${INCLUDE_GOLANG_IMAGE:-1}"
REDROID_TAG="${REDROID_TAG:-16.0.0_64only-latest}"
OUT_DIR="${OUT_DIR:-${ONE_CLICK_DIR}/dist}"
KIT_ROOT="${OUT_DIR}/${RELEASE_TAG}"
BUNDLE_TAR="${OUT_DIR}/${RELEASE_TAG}.tar.gz"
SHA_PATH="${BUNDLE_TAR}.sha256"

GO_TARBALL="go${GO_VERSION}.linux-arm64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
INFRA_REPO="${INFRA_REPO:-https://github.com/e2b-dev/infra.git}"

require_cmd curl
require_cmd tar
require_cmd git

if [[ "${INCLUDE_REDROID}" == "1" || "${INCLUDE_GOLANG_IMAGE}" == "1" ]]; then
  require_cmd docker
fi

rm -rf "${KIT_ROOT}"
mkdir -p "${KIT_ROOT}"/{go,src,images,scripts}

log "=== offline build kit: ${RELEASE_TAG} ==="
log "ENVD_REF=${ENVD_REF} GO_VERSION=${GO_VERSION} INCLUDE_REDROID=${INCLUDE_REDROID} INCLUDE_GOLANG_IMAGE=${INCLUDE_GOLANG_IMAGE}"

# --- Go toolchain (linux/arm64 native on Kunpeng) ---
if [[ ! -f "${KIT_ROOT}/go/${GO_TARBALL}" ]]; then
  log "downloading ${GO_URL}"
  curl -fsSL "${GO_URL}" -o "${KIT_ROOT}/go/${GO_TARBALL}"
fi
(
  cd "${KIT_ROOT}/go"
  sha256sum "${GO_TARBALL}" > "${GO_TARBALL}.sha256"
)

# --- e2b-dev/infra with vendored modules ---
log "cloning ${INFRA_REPO} @ ${ENVD_REF}"
git clone --depth 1 --branch "${ENVD_REF}" "${INFRA_REPO}" "${KIT_ROOT}/src/infra"

if ! command -v go >/dev/null 2>&1 || ! go version | grep -q "go${GO_VERSION} "; then
  log "using bundled Go ${GO_VERSION} toolchain for go mod vendor"
  rm -rf /tmp/go-toolchain-offline-kit
  mkdir -p /tmp/go-toolchain-offline-kit
  tar -C /tmp/go-toolchain-offline-kit -xzf "${KIT_ROOT}/go/${GO_TARBALL}"
  export PATH="/tmp/go-toolchain-offline-kit/go/bin:${PATH}"
fi

go version
log "go mod vendor in packages/envd"
(
  cd "${KIT_ROOT}/src/infra/packages/envd"
  export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
  export GOWORK=off
  go mod vendor
)

# Record exact infra commit
git -C "${KIT_ROOT}/src/infra" rev-parse HEAD > "${KIT_ROOT}/src/infra.commit"

# --- envd-starter + image overlay files from this repo ---
log "copying envd-starter and android overlay files"
cp -a "${ENVD_IMAGE_DIR}/envd-starter" "${KIT_ROOT}/src/envd-starter"
cp -a "${ENVD_IMAGE_DIR}/android-init" "${KIT_ROOT}/src/android-init"
cp -a "${ENVD_IMAGE_DIR}/android-redroid-entrypoint.sh" "${KIT_ROOT}/src/"
cp -a "${ENVD_IMAGE_DIR}/start-cube-envd.sh" "${KIT_ROOT}/src/"
cp -a "${ENVD_IMAGE_DIR}/lib" "${KIT_ROOT}/src/lib"
cp -a "${ENVD_IMAGE_DIR}/verify-envd-health.sh" "${KIT_ROOT}/src/"
cp -a "${SCRIPT_DIR}/Dockerfile.offline" "${KIT_ROOT}/"
cp -a "${SCRIPT_DIR}/Dockerfile.inject" "${KIT_ROOT}/"
cp -a "${SCRIPT_DIR}/kunpeng/"*.sh "${KIT_ROOT}/scripts/"
chmod +x "${KIT_ROOT}/scripts/"*.sh
cp -a "${SCRIPT_DIR}/README_OFFLINE_KUNPENG.md" "${KIT_ROOT}/README.md"

# --- optional: ReDroid base docker image ---
if [[ "${INCLUDE_REDROID}" == "1" ]]; then
  UPSTREAM="redroid/redroid:${REDROID_TAG}"
  LOCAL="redroid:${REDROID_TAG}"
  log "pulling ${UPSTREAM} (linux/arm64)"
  docker pull --platform linux/arm64 "${UPSTREAM}"
  docker tag "${UPSTREAM}" "${LOCAL}"
  ARCH="$(docker image inspect "${UPSTREAM}" --format '{{.Architecture}}')"
  [[ "${ARCH}" == "arm64" ]] || die "redroid image arch is ${ARCH}, expected arm64"
  REDROID_TAR="${KIT_ROOT}/images/redroid-${REDROID_TAG}-arm64-docker.tar.gz"
  log "exporting docker images to ${REDROID_TAR}"
  docker save "${UPSTREAM}" "${LOCAL}" | gzip -c > "${REDROID_TAR}"
  sha256sum "${REDROID_TAR}" > "${REDROID_TAR}.sha256"
fi

# --- optional: golang builder docker image ---
if [[ "${INCLUDE_GOLANG_IMAGE}" == "1" ]]; then
  GOLANG_IMAGE="golang:${GO_VERSION}-bookworm"
  log "pulling ${GOLANG_IMAGE}"
  docker pull --platform linux/arm64 "${GOLANG_IMAGE}"
  GOLANG_TAR="${KIT_ROOT}/images/golang-${GO_VERSION}-bookworm-arm64-docker.tar.gz"
  docker save "${GOLANG_IMAGE}" | gzip -c > "${GOLANG_TAR}"
  sha256sum "${GOLANG_TAR}" > "${GOLANG_TAR}.sha256"
fi

# --- manifest ---
cat > "${KIT_ROOT}/MANIFEST.json" <<EOF
{
  "kit_version": "${RELEASE_TAG}",
  "envd_ref": "${ENVD_REF}",
  "infra_commit": "$(cat "${KIT_ROOT}/src/infra.commit")",
  "go_version": "${GO_VERSION}",
  "redroid_tag": "${REDROID_TAG}",
  "include_redroid_image": ${INCLUDE_REDROID},
  "include_golang_image": ${INCLUDE_GOLANG_IMAGE},
  "target_goos": "android",
  "target_goarch": "arm64",
  "envd_port": 49983
}
EOF

log "creating ${BUNDLE_TAR}"
tar -C "${OUT_DIR}" -czf "${BUNDLE_TAR}" "${RELEASE_TAG}"
SHA="$(sha256sum "${BUNDLE_TAR}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "$(basename "${BUNDLE_TAR}")" > "${SHA_PATH}"

log "offline build kit ready:"
log "  bundle: ${BUNDLE_TAR}"
log "  sha256: ${SHA}"
log "  size:   $(du -h "${BUNDLE_TAR}" | awk '{print $1}')"
log "on Kunpeng: tar xzf $(basename "${BUNDLE_TAR}") && cd ${RELEASE_TAG} && ./scripts/01-install-go.sh"
