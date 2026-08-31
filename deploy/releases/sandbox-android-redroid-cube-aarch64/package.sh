#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="sandbox-android-redroid-cube-aarch64"
GIT_SHORT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
BUILD_DATE="$(date -u +'%Y-%m-%d')"
STARTER_SRC="${ROOT_DIR}/deploy/sandbox-images/sandbox-android-redroid-cube/fd-sanitize-starter"

STAGE="${RELEASE_DIR}/.stage-${GIT_SHORT}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/${PKG_NAME}/bin" "${STAGE}/${PKG_NAME}/examples"

echo "==> Cross-compile fd-sanitize-starter (linux/arm64)"
(
  cd "${STARTER_SRC}"
  GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -ldflags "-s -w" -o "${STAGE}/${PKG_NAME}/bin/fd-sanitize-starter" .
)

file "${STAGE}/${PKG_NAME}/bin/fd-sanitize-starter" | grep -q 'ARM aarch64'

cp -a "${RELEASE_DIR}/INSTALL.md" \
  "${RELEASE_DIR}/Dockerfile.inject" \
  "${RELEASE_DIR}/build-docker-image.sh" \
  "${RELEASE_DIR}/build-offline-docker-bundle.sh" \
  "${STAGE}/${PKG_NAME}/"
chmod +x "${STAGE}/${PKG_NAME}/build-docker-image.sh" \
         "${STAGE}/${PKG_NAME}/build-offline-docker-bundle.sh" \
         "${STAGE}/${PKG_NAME}/bin/fd-sanitize-starter"

cp -a "${ROOT_DIR}/deploy/sandbox-images/sandbox-android-redroid-cube/examples/redroid-cold-fd-sanitize.json" \
  "${STAGE}/${PKG_NAME}/examples/"

cat > "${STAGE}/${PKG_NAME}/BUILDINFO" <<EOF
name=${PKG_NAME}
date=${BUILD_DATE}
git_commit=${GIT_COMMIT}
git_short=${GIT_SHORT}
target=linux/arm64
binary=fd-sanitize-starter (static, GOOS=android container entry)
fix=clear inherited cube-agent FIFO fds before ReDroid exec /init
image_tag=sandbox-android-redroid-cube:16.0.0-arm64
EOF

OUT="${RELEASE_DIR}/${PKG_NAME}-${GIT_SHORT}.tar.gz"
tar -C "${STAGE}" -czf "${OUT}" "${PKG_NAME}"
sha256sum "${OUT}" > "${OUT}.sha256"
rm -rf "${STAGE}"

echo "OK: ${OUT}"
cat "${OUT}.sha256"
