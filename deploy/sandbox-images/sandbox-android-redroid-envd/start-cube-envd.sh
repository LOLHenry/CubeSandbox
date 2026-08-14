#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
# Start envd for CubeVM/ReDroid (not Firecracker). -isnotfc is required outside FC.
set -eu

ENVD_PORT="${ENVD_PORT:-49983}"
ENVD_LOG="${ENVD_LOG:-/data/local/tmp/envd.log}"
ENVD_BIN="${ENVD_BIN:-/usr/bin/envd}"
STARTER_LOG="${ENVD_STARTER_LOG:-/data/local/tmp/envd-initrc.log}"

log() {
  msg="$(date -Iseconds 2>/dev/null || date) initrc-envd: $*"
  echo "${msg}" >>"${STARTER_LOG}" 2>/dev/null || echo "${msg}" >>/tmp/envd-initrc.log
  echo "${msg}" >&2
}

mkdir -p "$(dirname "${ENVD_LOG}")" "$(dirname "${STARTER_LOG}")" 2>/dev/null || true

log "starting ${ENVD_BIN} -isnotfc -port ${ENVD_PORT} (log=${ENVD_LOG})"
if [ ! -x "${ENVD_BIN}" ]; then
  log "ERROR: ${ENVD_BIN} not executable"
  exit 1
fi

exec "${ENVD_BIN}" -isnotfc -port "${ENVD_PORT}" >>"${ENVD_LOG}" 2>&1
