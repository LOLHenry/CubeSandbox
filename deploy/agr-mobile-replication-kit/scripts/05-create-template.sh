#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

: "${CUBEMASTER_URL:=http://127.0.0.1:8089}"
IMAGE_TAG="${TEMPLATE_IMAGE:-sandbox-android-redroid-envd:16.0.0-arm64}"
CPU="${TEMPLATE_CPU:-4000}"
MEM="${TEMPLATE_MEMORY:-6144}"
LAYER="${TEMPLATE_WRITABLE_LAYER:-10Gi}"

if ! command -v cubemastercli >/dev/null; then
  echo "cubemastercli not found" >&2
  exit 1
fi

echo "==> Create template from ${IMAGE_TAG}"
cubemastercli tpl create-from-image \
  --image "$IMAGE_TAG" \
  --writable-layer-size "$LAYER" \
  --expose-port 5555 \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --cpu "$CPU" \
  --memory "$MEM"

echo "==> List templates"
cubemastercli tpl list | tail -5
