#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="cube-agent-android-fd-sanitize-fix-aarch64"
GIT_SHORT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
BUILD_DATE="$(date -u +'%Y-%m-%d')"

SRC_BIN="${1:-${ROOT_DIR}/agent/target/aarch64-unknown-linux-musl/release/cube-agent}"
if [[ ! -f "${SRC_BIN}" ]]; then
  echo "ERROR: missing ${SRC_BIN}" >&2
  exit 1
fi

STAGE="${RELEASE_DIR}/.stage-${GIT_SHORT}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/${PKG_NAME}/bin"
cp -a "${SRC_BIN}" "${STAGE}/${PKG_NAME}/bin/cube-agent"
cp -a "${RELEASE_DIR}/INSTALL.md" "${RELEASE_DIR}/install-guest-image.sh" \
  "${STAGE}/${PKG_NAME}/"
chmod +x "${STAGE}/${PKG_NAME}/install-guest-image.sh"

cat > "${STAGE}/${PKG_NAME}/BUILDINFO" <<EOF
name=${PKG_NAME}
date=${BUILD_DATE}
git_commit=${GIT_COMMIT}
git_short=${GIT_SHORT}
target=aarch64-unknown-linux-musl
profile=release
fix=sanitize inherited FIFO fds for Android ReDroid boot
EOF

OUT="${RELEASE_DIR}/${PKG_NAME}-${GIT_SHORT}.tar.gz"
tar -C "${STAGE}" -czf "${OUT}" "${PKG_NAME}"
sha256sum "${OUT}" > "${OUT}.sha256"
rm -rf "${STAGE}"

echo "OK: ${OUT}"
cat "${OUT}.sha256"
