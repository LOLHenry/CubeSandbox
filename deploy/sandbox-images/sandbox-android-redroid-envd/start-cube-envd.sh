#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
# Start envd for CubeVM/ReDroid (not Firecracker). -isnotfc is required outside FC.
ENVD_PORT="${ENVD_PORT:-49983}"
ENVD_LOG="${ENVD_LOG:-/data/local/tmp/envd.log}"
ENVD_BIN="${ENVD_BIN:-/usr/bin/envd}"
mkdir -p "$(dirname "${ENVD_LOG}")"
exec "${ENVD_BIN}" -isnotfc -port "${ENVD_PORT}" >>"${ENVD_LOG}" 2>&1
