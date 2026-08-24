#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build inner offline-build-kit on a networked arm64 machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
OFFLINE_KIT="${REPO_ROOT}/deploy/sandbox-images/sandbox-android-redroid-envd/offline-build-kit"

RELEASE_TAG="${RELEASE_TAG:-agr-mobile-replication-kit}"
INCLUDE_REDROID="${INCLUDE_REDROID:-1}"

echo "==> Building nested envd offline kit"
cd "$OFFLINE_KIT"
RELEASE_TAG="$RELEASE_TAG" INCLUDE_REDROID="$INCLUDE_REDROID" ./build-offline-kit.sh

echo "==> Done. Inner kit at: ${OFFLINE_KIT}/dist/${RELEASE_TAG}/"
