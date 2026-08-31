#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
SSH_PORT="${SSH_PORT:-10022}"
VM_USER="${VM_USER:-opencloudos}"
VM_PASSWORD="${VM_PASSWORD:-opencloudos}"

sshpass -p "${VM_PASSWORD}" ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -p "${SSH_PORT}" "${VM_USER}@127.0.0.1" 'sudo bash -s' <<'GUEST'
set -euo pipefail
export CUBE_PVM_ENABLE=0 MIRROR=cn
export CUBE_SANDBOX_NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')"
export CUBE_SANDBOX_NETWORK_CIDR=10.100.0.0/18
if curl -sf http://127.0.0.1:3000/health >/dev/null; then
  echo "[guest-oneclick] already installed"
else
  curl -fsSL https://raw.githubusercontent.com/tencentcloud/CubeSandbox/master/deploy/one-click/online-install.sh | sudo bash
fi
curl -sf http://127.0.0.1:3000/health
sudo /usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh
GUEST

curl -sf "http://127.0.0.1:13000/health" && echo "[guest-oneclick] M0 OK — CubeAPI :13000 WebUI :12088"
