#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install bison/flex from bundled openEuler RPMs (offline Kunpeng host).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_DIR="${ROOT}/rpms"

if [[ ! -d "${RPM_DIR}" ]]; then
  echo "ERROR: ${RPM_DIR} not found; run from extracted offline bundle root" >&2
  exit 1
fi

shopt -s nullglob
rpms=("${RPM_DIR}"/*.rpm)
if (( ${#rpms[@]} == 0 )); then
  echo "ERROR: no RPMs under ${RPM_DIR}" >&2
  exit 1
fi

if command -v dnf >/dev/null 2>&1; then
  dnf install -y "${rpms[@]}"
elif command -v yum >/dev/null 2>&1; then
  yum install -y "${rpms[@]}"
elif command -v rpm >/dev/null 2>&1; then
  rpm -Uvh --nodeps "${rpms[@]}"
else
  echo "ERROR: need dnf, yum, or rpm" >&2
  exit 1
fi

command -v bison >/dev/null
command -v flex >/dev/null
echo "OK: bison=$(bison --version | head -1)"
echo "OK: flex=$(flex --version | head -1)"
