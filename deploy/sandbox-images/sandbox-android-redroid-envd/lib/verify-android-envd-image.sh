#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Verify envd inside a sandbox-android-redroid-envd image is Android/bionic ELF.
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

FILE_OUT="$(docker run --rm --entrypoint /system/bin/sh "${IMAGE}" -c 'file /usr/bin/envd')"
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
