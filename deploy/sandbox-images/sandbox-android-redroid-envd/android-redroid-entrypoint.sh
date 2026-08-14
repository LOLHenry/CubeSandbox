#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# ReDroid ships with Android /init as its main entry. CubeSandbox cubebox templates
# require envd on :49983 for health probes and SDK I/O. Start envd in the
# background, then hand off to the original ReDroid init.
set -eu

ENVD_PORT="${ENVD_PORT:-49983}"
ENVD_BIN="${ENVD_BIN:-/usr/bin/envd}"
ENVD_LOG="${ENVD_LOG:-/data/local/tmp/envd.log}"

if [ ! -x "${ENVD_BIN}" ]; then
  echo "android-redroid-entrypoint: envd not executable at ${ENVD_BIN}" >&2
  exec /init "$@"
fi

mkdir -p "$(dirname "${ENVD_LOG}")"
n=0
while [ "${n}" -lt 3 ]; do
  "${ENVD_BIN}" -port "${ENVD_PORT}" >>"${ENVD_LOG}" 2>&1 &
  ENVD_PID=$!
  sleep 1
  if kill -0 "${ENVD_PID}" 2>/dev/null; then
    break
  fi
  n=$((n + 1))
done

if ! kill -0 "${ENVD_PID}" 2>/dev/null; then
  echo "android-redroid-entrypoint: envd failed to start after ${n} attempt(s); see ${ENVD_LOG}" >&2
  tail -n 20 "${ENVD_LOG}" >&2 || true
fi

exec /init "$@"
