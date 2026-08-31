#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M3: Import amd64 envd image into guest Docker/containerd and run template E2E.
#
# Cloud Agent notes:
#   - cubecli defaults to --timeout 60s; large imports need CUBECLI_TIMEOUT (e.g. 30m).
#   - CubeMaster native export pulls from registry; local images need
#     CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false + docker load + matching tag.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"
HOST_IMAGE="${HOST_IMAGE:-sandbox-android-redroid-envd:16.0.0-amd64}"
IMAGE_REF="${IMAGE_REF:-docker.io/library/sandbox-android-redroid-envd:16.0.0-amd64}"
CUBECLI_TIMEOUT="${CUBECLI_TIMEOUT:-30m}"
IMPORT_TO_CONTAINERD="${IMPORT_TO_CONTAINERD:-1}"
SKIP_SCP="${SKIP_SCP:-0}"
GUEST_TAR="${GUEST_TAR:-/tmp/m3-image.tar}"
TAR="/tmp/m3-image-$$.tar"

log() { printf '[m3-guest] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }
cleanup() { rm -f "${TAR}"; }
trap cleanup EXIT

docker image inspect "${HOST_IMAGE}" >/dev/null 2>&1 || die "host image missing: ${HOST_IMAGE}"

if [[ "${SKIP_SCP}" != "1" ]]; then
  log "exporting ${HOST_IMAGE}"
  docker save "${HOST_IMAGE}" -o "${TAR}"

  log "uploading to guest (${GUEST_TAR})"
  sshpass -p "${VM_PASSWORD}" scp \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -P "${SSH_PORT}" "${TAR}" "${VM_USER}@127.0.0.1:${GUEST_TAR}"
else
  log "SKIP_SCP=1 — reusing existing guest tar ${GUEST_TAR}"
fi

log "loading image in guest Docker + optional containerd import"
sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" \
  "IMAGE_REF=${IMAGE_REF} GUEST_TAR=${GUEST_TAR} CUBECLI_TIMEOUT=${CUBECLI_TIMEOUT} IMPORT_TO_CONTAINERD=${IMPORT_TO_CONTAINERD} bash -s" <<'GUEST'
set -euo pipefail
export PATH="/usr/local/bin:/usr/local/services/cubetoolbox/bin:${PATH}"
IMAGE_REF="${IMAGE_REF:-docker.io/library/sandbox-android-redroid-envd:16.0.0-amd64}"
GUEST_TAR="${GUEST_TAR:-/tmp/m3-image.tar}"
CUBECLI_TIMEOUT="${CUBECLI_TIMEOUT:-30m}"
IMPORT_TO_CONTAINERD="${IMPORT_TO_CONTAINERD:-1}"
ENV_FILE="/usr/local/services/cubetoolbox/.one-click.env"
TAG="${IMAGE_REF##*:}"

docker() { sudo docker "$@"; }

log() { printf '[m3-import] %s\n' "$*"; }

[[ -f "${GUEST_TAR}" ]] || { echo "missing ${GUEST_TAR}" >&2; exit 1; }

log "docker load from ${GUEST_TAR}"
docker load -i "${GUEST_TAR}"
docker tag "sandbox-android-redroid-envd:${TAG}" "${IMAGE_REF}"
docker image inspect "${IMAGE_REF}" >/dev/null

# Template PULLING uses CubeMaster export path. Native export always hits registry;
# disable it when using offline/local images only.
if grep -q '^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=' "${ENV_FILE}" 2>/dev/null; then
  sudo sed -i 's/^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=.*/CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false/' "${ENV_FILE}"
else
  echo 'CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false' | sudo tee -a "${ENV_FILE}" >/dev/null
fi
log "restart cubemaster (use local Docker for template export)"
sudo systemctl restart cube-sandbox-cubemaster.service
sleep 5
sudo systemctl is-active --quiet cube-sandbox-cubemaster.service

if [[ "${IMPORT_TO_CONTAINERD}" == "1" ]]; then
  log "ctr-image import (timeout=${CUBECLI_TIMEOUT})"
  sudo cubecli --timeout "${CUBECLI_TIMEOUT}" image ctr-image import \
    --base-name docker.io/library/sandbox-android-redroid-envd "${GUEST_TAR}"
  sudo cubecli image ls | grep sandbox-android || true
fi
GUEST

sshpass -p "${VM_PASSWORD}" scp \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -P "${SSH_PORT}" "${SCRIPT_DIR}/08-guest-e2e-template-inner.sh" \
  "${VM_USER}@127.0.0.1:/tmp/m3-e2e-inner.sh"

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" \
  "chmod +x /tmp/m3-e2e-inner.sh && IMAGE=${IMAGE_REF} JOB_TIMEOUT_SEC=${JOB_TIMEOUT_SEC:-3600} PROBE_TIMEOUT_MS=${PROBE_TIMEOUT_MS:-600000} bash /tmp/m3-e2e-inner.sh"

log "M3 OK — template READY"
