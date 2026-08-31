#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Bundle Linux kernel source + openEuler aarch64 build deps for offline guest-kernel
# builds on Kunpeng (yellow zone / no outbound internet).
#
# Usage (networked machine):
#   ./deploy/one-click/scripts/one-click/build-guest-kernel-offline-bundle.sh
#   RELEASE_TAG=preview ./build-guest-kernel-offline-bundle.sh
#
# Output:
#   deploy/one-click/dist/cube-guest-kernel-build-offline-aarch64[-<tag>].tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONE_CLICK_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${ONE_CLICK_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${ONE_CLICK_DIR}/lib/common.sh"

KERNEL_VERSION="${KERNEL_VERSION:-6.6.119}"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}}"
OPENEULER_REPO_BASE="${OPENEULER_REPO_BASE:-https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/aarch64/Packages}"
BISON_RPM="${BISON_RPM:-bison-3.8.2-2.oe2203sp4.aarch64.rpm}"
FLEX_RPM="${FLEX_RPM:-flex-2.6.4-5.oe2203sp4.aarch64.rpm}"
OUT_DIR="${OUT_DIR:-${ONE_CLICK_DIR}/dist}"
RELEASE_TAG="${RELEASE_TAG:-${CUBE_VERSION:-}}"

if [[ -n "${RELEASE_TAG}" ]]; then
  BUNDLE_NAME="${BUNDLE_NAME:-cube-guest-kernel-build-offline-aarch64-${RELEASE_TAG}.tar.gz}"
else
  BUNDLE_NAME="${BUNDLE_NAME:-cube-guest-kernel-build-offline-aarch64.tar.gz}"
fi
OUT_PATH="${OUT_DIR}/${BUNDLE_NAME}"
SHA_PATH="${OUT_PATH}.sha256"

require_cmd curl
require_cmd sha256sum
require_cmd tar
mkdir -p "${OUT_DIR}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
STAGE="${TMP_DIR}/guest-kernel-build-offline-aarch64"
mkdir -p "${STAGE}/rpms" "${STAGE}/configs"

log "download kernel source: ${KERNEL_URL}"
curl -fL --http1.1 --retry 5 --retry-delay 3 --retry-all-errors \
  -o "${STAGE}/${KERNEL_TARBALL}" "${KERNEL_URL}"

log "download openEuler rpms (aarch64)"
curl -fL --retry 3 -o "${STAGE}/rpms/${BISON_RPM}" \
  "${OPENEULER_REPO_BASE}/${BISON_RPM}"
curl -fL --retry 3 -o "${STAGE}/rpms/${FLEX_RPM}" \
  "${OPENEULER_REPO_BASE}/${FLEX_RPM}"

log "copy in-tree kernel config"
cp "${REPO_ROOT}/configs/kernel-oc9.aarch64.config" "${STAGE}/configs/"

log "copy install helper"
cp "${REPO_ROOT}/offline-pkgs/guest-kernel-build/install-guest-kernel-deps.sh" "${STAGE}/"
cp "${REPO_ROOT}/offline-pkgs/guest-kernel-build/README.md" "${STAGE}/"
chmod +x "${STAGE}/install-guest-kernel-deps.sh"

KERNEL_SHA="$(sha256sum "${STAGE}/${KERNEL_TARBALL}" | awk '{print $1}')"
BISON_SHA="$(sha256sum "${STAGE}/rpms/${BISON_RPM}" | awk '{print $1}')"
FLEX_SHA="$(sha256sum "${STAGE}/rpms/${FLEX_RPM}" | awk '{print $1}')"

cat > "${STAGE}/MANIFEST.json" <<EOF
{
  "bundle": "cube-guest-kernel-build-offline-aarch64",
  "kernel_version": "${KERNEL_VERSION}",
  "kernel_tarball": "${KERNEL_TARBALL}",
  "kernel_sha256": "${KERNEL_SHA}",
  "openeuler_release": "22.03-LTS-SP4",
  "rpms": {
    "bison": {
      "file": "rpms/${BISON_RPM}",
      "sha256": "${BISON_SHA}"
    },
    "flex": {
      "file": "rpms/${FLEX_RPM}",
      "sha256": "${FLEX_SHA}"
    }
  },
  "kernel_config": "configs/kernel-oc9.aarch64.config",
  "build_command": "make guest-kernel KERNEL_SRC=./linux-${KERNEL_VERSION} KERNEL_TARGET_ARCH=aarch64"
}
EOF

log "create tarball ${OUT_PATH}"
tar -C "${TMP_DIR}" -czf "${OUT_PATH}" "$(basename "${STAGE}")"
sha256sum "${OUT_PATH}" > "${SHA_PATH}"

log "offline guest-kernel build bundle ready:"
log "  ${OUT_PATH}"
log "  ${SHA_PATH}"
log "  kernel_sha256=${KERNEL_SHA}"
