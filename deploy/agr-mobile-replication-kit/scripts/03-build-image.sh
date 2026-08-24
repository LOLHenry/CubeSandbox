#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_ROOT="${KIT_ROOT:-$ROOT}"

if [[ -f "${KIT_ROOT}/inner-kit/MANIFEST.json" ]]; then
  INNER="${KIT_ROOT}/inner-kit"
elif [[ -d "${KIT_ROOT}/scripts/02-build-binaries.sh" ]]; then
  INNER="$KIT_ROOT"
else
  echo "Cannot find inner offline kit under KIT_ROOT=${KIT_ROOT}" >&2
  exit 1
fi

export PATH="/usr/local/go/bin:${PATH:-}"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-envd:16.0.0-arm64}"

echo "==> Build binaries (GOOS=android)"
"${INNER}/scripts/02-build-binaries.sh"

echo "==> Build docker image (inject mode)"
DOCKER_BUILDKIT=0 IMAGE_TAG="$IMAGE_TAG" "${INNER}/scripts/03-build-docker-image.sh"

echo "==> Image: ${IMAGE_TAG}"
