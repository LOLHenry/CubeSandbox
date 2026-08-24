#!/usr/bin/env bash
# Verify offline-built image: Android envd ELF + optional privileged smoke test.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-sandbox-android-redroid-envd:16.0.0-arm64}"

if [[ -x "${KIT_ROOT}/src/lib/verify-android-envd-image.sh" ]]; then
  echo "==> verify-android-envd-image.sh"
  "${KIT_ROOT}/src/lib/verify-android-envd-image.sh" "${IMAGE}"
fi

if [[ "${RUN_SMOKE:-0}" == "1" && -x "${KIT_ROOT}/src/verify-envd-health.sh" ]]; then
  echo "==> verify-envd-health.sh (privileged docker run)"
  IMAGE="${IMAGE}" "${KIT_ROOT}/src/verify-envd-health.sh"
fi

echo "OK: verification passed for ${IMAGE}"
