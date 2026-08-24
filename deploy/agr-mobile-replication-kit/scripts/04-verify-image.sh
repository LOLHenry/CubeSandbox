#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_ROOT="${KIT_ROOT:-$ROOT}"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-envd:16.0.0-arm64}"

INNER="${KIT_ROOT}/inner-kit"
if [[ ! -d "$INNER" ]]; then
  INNER="$KIT_ROOT"
fi

echo "==> Verify image ${IMAGE_TAG}"
"${INNER}/scripts/04-verify.sh" "$IMAGE_TAG"

echo "==> Smoke: envd health in container"
CID="$(docker run -d --rm --privileged "$IMAGE_TAG")"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
sleep 15
docker exec "$CID" file /usr/bin/envd
docker exec "$CID" toybox wget -q -O /dev/null http://127.0.0.1:49983/health && echo "envd /health OK"
echo "==> Verify passed"
