#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# M3: Import amd64 envd image into guest containerd and run template E2E.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"
HOST_IMAGE="${HOST_IMAGE:-sandbox-android-redroid-envd:16.0.0-amd64}"
IMAGE_REF="${IMAGE_REF:-docker.io/library/sandbox-android-redroid-envd:16.0.0-amd64}"
TAR="/tmp/m3-image-$$.tar"

log() { printf '[m3-guest] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }
cleanup() { rm -f "${TAR}"; }
trap cleanup EXIT

docker image inspect "${HOST_IMAGE}" >/dev/null 2>&1 || die "host image missing: ${HOST_IMAGE}"

log "exporting ${HOST_IMAGE}"
docker save "${HOST_IMAGE}" -o "${TAR}"

log "uploading and importing into guest containerd"
sshpass -p "${VM_PASSWORD}" scp \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -P "${SSH_PORT}" "${TAR}" "${VM_USER}@127.0.0.1:/tmp/m3-image.tar"

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" \
  "IMAGE_REF=${IMAGE_REF} bash -s" <<'GUEST'
set -euo pipefail
export PATH="/usr/local/bin:/usr/local/services/cubetoolbox/bin:${PATH}"
IMAGE_REF="${IMAGE_REF:-docker.io/library/sandbox-android-redroid-envd:16.0.0-amd64}"
echo "[m3] ctr-image import"
sudo cubecli image ctr-image import --base-name docker.io/library/sandbox-android-redroid-envd /tmp/m3-image.tar
sudo cubecli image ls | grep sandbox-android || true
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
  "chmod +x /tmp/m3-e2e-inner.sh && IMAGE=${IMAGE_REF} bash /tmp/m3-e2e-inner.sh"

log "M3 OK — template READY"
