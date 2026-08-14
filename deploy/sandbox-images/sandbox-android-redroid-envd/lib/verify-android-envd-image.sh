#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Verify envd inside a sandbox-android-redroid-envd image is Android/bionic ELF.
# Extracts /usr/bin/envd to the host (no container exec required).
# Usage: verify-android-envd-image.sh <image-ref>
set -euo pipefail

IMAGE="${1:?image ref required}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: image not found: ${IMAGE}" >&2
  exit 1
fi

ARCH="$(docker image inspect "${IMAGE}" --format '{{.Architecture}}')"
if [[ "${ARCH}" != "arm64" ]]; then
  echo "ERROR: expected arm64 image, got ${ARCH}" >&2
  exit 1
fi

TMP_BIN="$(mktemp)"
CID="$(docker create "${IMAGE}")"
cleanup() {
  docker rm -f "${CID}" >/dev/null 2>&1 || true
  rm -f "${TMP_BIN}"
}
trap cleanup EXIT

docker cp "${CID}:/usr/bin/envd" "${TMP_BIN}"

FILE_OUT="$(file "${TMP_BIN}")"
echo "${FILE_OUT}"

if echo "${FILE_OUT}" | grep -q 'statically linked'; then
  echo "ERROR: envd is GOOS=linux static binary; ReDroid requires GOOS=android (linker64)" >&2
  exit 1
fi

if ! echo "${FILE_OUT}" | grep -q 'interpreter /system/bin/linker64'; then
  echo "ERROR: envd is not an Android/bionic binary" >&2
  exit 1
fi

echo "OK: envd is Android/bionic (${IMAGE})"
