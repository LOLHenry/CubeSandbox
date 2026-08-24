#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Smoke test: run sandbox and check envd + adb ports (requires READY template).
set -euo pipefail

TEMPLATE_ID="${1:-}"
IMAGE_TAG="${IMAGE_TAG:-sandbox-android-redroid-envd:16.0.0-arm64}"

if [[ -z "$TEMPLATE_ID" ]]; then
  echo "Usage: $0 <template-id>" >&2
  echo "Or set TEMPLATE_ID env var" >&2
  exit 1
fi

if command -v cubemastercli >/dev/null; then
  echo "==> Run sandbox from template ${TEMPLATE_ID}"
  OUT="$(cubemastercli run -t "$TEMPLATE_ID" 2>&1)" || true
  echo "$OUT"
  SID="$(echo "$OUT" | grep -oE 'sandbox-[a-z0-9-]+' | head -1 || true)"
  if [[ -n "$SID" ]]; then
    echo "Sandbox: $SID"
    cubemastercli info -s "$SID" || true
  fi
else
  echo "cubemastercli missing; docker-only smoke"
  CID="$(docker run -d --rm --privileged -p 15555:5555 -p 149983:49983 "$IMAGE_TAG")"
  trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
  sleep 20
  curl -s -o /dev/null -w "host envd => %{http_code}\n" http://127.0.0.1:149983/health
  if command -v adb >/dev/null; then
    adb connect 127.0.0.1:15555 || true
    adb -s 127.0.0.1:15555 shell getprop ro.build.version.release || true
  fi
fi
