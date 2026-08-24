#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "OK  $name"
  else
    echo "FAIL $name"
    FAIL=1
  fi
}

echo "==> AGR Mobile Replication Kit preflight"
echo "arch: $(uname -m)"
echo "kit:  $ROOT"

[[ "$(uname -m)" == "aarch64" ]] || { echo "WARN: expected aarch64 for Kunpeng target"; }

check "kvm device" test -e /dev/kvm
check "docker" docker info
check "go (optional if using offline bundle)" command -v go
check "cubemastercli (optional for template step)" command -v cubemastercli
check "adb (optional for adb test)" command -v adb

if docker info 2>/dev/null | grep -q 'Architecture: aarch64'; then
  echo "OK  docker arm64"
else
  echo "WARN docker may not be arm64"
fi

if [[ -f "${ROOT}/../sandbox-images/sandbox-android-redroid-envd/offline-build-kit/build-offline-kit.sh" ]]; then
  echo "OK  nested offline-build-kit present"
else
  echo "FAIL nested offline-build-kit missing"
  FAIL=1
fi

exit "$FAIL"
