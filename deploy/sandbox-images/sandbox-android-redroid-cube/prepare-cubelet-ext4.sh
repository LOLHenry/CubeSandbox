#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Register sandbox-android-redroid-cube:16.0.0-arm64 as a cubebox ext4 rootfs
# on all Cubelet nodes. Required before:
#   cubemastercli multirun --norm examples/redroid-cold-fd-sanitize.json
#
# multirun with storage_media=ext4 does NOT pull from Docker directly; Cubelet
# expects the pmem/ext4 artifact under cubebox_os_image (built via create-from-image).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-sandbox-android-redroid-cube:16.0.0-arm64}"
WRITABLE="${WRITABLE:-10Gi}"
CPU="${CPU:-4000}"
MEMORY="${MEMORY:-6144}"
EXPOSE_PORT="${EXPOSE_PORT:-5555}"
NATIVE_ENV="${NATIVE_ENV:-/usr/local/services/cubetoolbox/.one-click.env}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker required"
command -v cubemastercli >/dev/null || die "cubemastercli required"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "==> Docker image ${IMAGE} missing; building..."
  "${SCRIPT_DIR}/build-docker-image.sh"
fi

ARCH="$(docker image inspect "${IMAGE}" --format '{{.Architecture}}')"
[[ "${ARCH}" == "arm64" ]] || die "${IMAGE} is ${ARCH}, need arm64"

EP="$(docker image inspect "${IMAGE}" --format '{{json .Config.Entrypoint}}')"
echo "==> Docker OK: arch=${ARCH} entrypoint=${EP}"

if [[ -f "${NATIVE_ENV}" ]]; then
  if grep -q '^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=' "${NATIVE_ENV}"; then
    if ! grep -q '^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false' "${NATIVE_ENV}"; then
      echo "WARN: set CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false in ${NATIVE_ENV} for local Docker images (README_KUNPENG §2.0)"
    fi
  else
    echo "WARN: append CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false to ${NATIVE_ENV} for offline/local Docker (README_KUNPENG §2.0)"
  fi
fi

PMEM="/usr/local/services/cubetoolbox/cubebox_os_image/cubebox/${IMAGE}/${IMAGE}.ext4"
if [[ -f "${PMEM}" ]]; then
  echo "==> ext4 already present: ${PMEM}"
  ls -lh "${PMEM}"
  exit 0
fi

echo "==> Building & distributing ext4 via cubemastercli tpl create-from-image"
echo "    (no envd probe — this image is FIFO-only validation)"

JOB_OUT="$(mktemp)"
set +e
cubemastercli tpl create-from-image \
  --image "${IMAGE}" \
  --writable-layer-size "${WRITABLE}" \
  --expose-port "${EXPOSE_PORT}" \
  --cpu "${CPU}" \
  --memory "${MEMORY}" \
  2>&1 | tee "${JOB_OUT}"
RC=${PIPESTATUS[0]}
set -e
[[ ${RC} -eq 0 ]] || die "create-from-image failed (exit ${RC})"

JOB_ID="$(sed -n 's/^job_id:[[:space:]]*//p' "${JOB_OUT}" | head -1)"
TPL_ID="$(sed -n 's/^template_id:[[:space:]]*//p' "${JOB_OUT}" | head -1)"
rm -f "${JOB_OUT}"

[[ -n "${JOB_ID}" ]] || die "could not parse job_id from create-from-image output"
echo "==> Watching job ${JOB_ID} (template ${TPL_ID:-unknown})"
cubemastercli tpl watch --job-id "${JOB_ID}"

if [[ -f "${PMEM}" ]]; then
  echo "OK: ext4 ready at ${PMEM}"
  ls -lh "${PMEM}"
else
  echo "WARN: ${PMEM} not found on this node yet."
  echo "      Multi-node clusters: wait for distribution or check cubemastercli tpl info ${TPL_ID:-<template-id>}"
fi

echo ""
echo "Next:"
echo "  cubemastercli multirun --norm examples/redroid-cold-fd-sanitize.json"
echo "  (JSON must keep storage_media=ext4; do NOT set cube.master.appsnapshot.template.id)"
