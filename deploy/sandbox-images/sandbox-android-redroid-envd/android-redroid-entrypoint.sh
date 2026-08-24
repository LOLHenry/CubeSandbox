#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# ReDroid + CubeVM: background envd (-isnotfc), then exec /init.
# Used when ENTRYPOINT points at this script (preview2/7 path).
set -eu

ADB_PORT="${CUBESANDBOX_ADB_PORT:-5555}"
ENVD_LOG="${ENVD_LOG:-/data/local/tmp/envd.log}"

if [ ! -x /usr/bin/start-cube-envd.sh ]; then
  echo "android-redroid-entrypoint: missing /usr/bin/start-cube-envd.sh" >&2
  exec /init "$@"
fi

mkdir -p "$(dirname "${ENVD_LOG}")"
n=0
while [ "${n}" -lt 3 ]; do
  /usr/bin/start-cube-envd.sh &
  ENVD_PID=$!
  sleep 1
  if kill -0 "${ENVD_PID}" 2>/dev/null; then
    break
  fi
  n=$((n + 1))
done

if ! kill -0 "${ENVD_PID}" 2>/dev/null; then
  echo "android-redroid-entrypoint: envd failed; see ${ENVD_LOG}" >&2
  tail -n 20 "${ENVD_LOG}" 2>/dev/null || true
fi

echo "android-redroid-entrypoint: envd pid=${ENVD_PID}; adbd on ${ADB_PORT}" >&2
exec /init "$@"
