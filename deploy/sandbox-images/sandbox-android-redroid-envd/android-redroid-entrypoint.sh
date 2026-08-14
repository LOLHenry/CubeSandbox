#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# ReDroid ships with Android /init as its main entry. CubeSandbox cubebox templates
# require envd on :49983 for health probes and SDK I/O. Start envd in the
# background, then hand off to the original ReDroid init.
set -eu

ENVD_PORT="${ENVD_PORT:-49983}"
ENVD_LOG="${ENVD_LOG:-/var/log/envd.log}"

mkdir -p "$(dirname "${ENVD_LOG}")"
/usr/bin/envd -port "${ENVD_PORT}" >>"${ENVD_LOG}" 2>&1 &

exec /init "$@"
