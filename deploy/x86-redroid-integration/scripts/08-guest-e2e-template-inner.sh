#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Runs inside dev-env guest — template from-image E2E.
set -euo pipefail
export PATH="/usr/local/bin:/usr/local/services/cubetoolbox/bin:${PATH}"
IMAGE="${IMAGE:-docker.io/library/sandbox-android-redroid-envd:16.0.0-amd64}"
CUBEMASTER_ADDR="${CUBEMASTER_ADDR:-127.0.0.1:8089}"
CUBEMASTERCLI="${CUBEMASTERCLI:-cubemastercli}"
PROBE_TIMEOUT_MS="${PROBE_TIMEOUT_MS:-180000}"
JOB_TIMEOUT_SEC="${JOB_TIMEOUT_SEC:-900}"

[[ -e /dev/kvm ]] || { echo "no /dev/kvm"; exit 1; }
sudo docker image inspect "${IMAGE}" >/dev/null

REQ="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
BODY="$(mktemp)"
RESP="$(mktemp)"
cat >"${BODY}" <<EOF
{
  "requestID": "${REQ}",
  "source_image_ref": "${IMAGE}",
  "writable_layer_size": "10Gi",
  "exposed_ports": [5555, 49983],
  "container_overrides": {
    "resources": { "cpu": "4000m", "mem": "6144Mi" },
    "probe": {
      "probe_handler": { "http_get": { "path": "/health", "port": 49983, "host": "" } },
      "timeout_ms": ${PROBE_TIMEOUT_MS},
      "period_ms": 500,
      "failure_threshold": 240,
      "success_threshold": 1
    }
  }
}
EOF

echo "[m3] POST /cube/template/from-image"
HTTP="$(curl -sS -o "${RESP}" -w '%{http_code}' \
  -X POST "http://${CUBEMASTER_ADDR}/cube/template/from-image" \
  -H 'Content-Type: application/json' --data-binary @"${BODY}")"
echo "[m3] HTTP ${HTTP}"
cat "${RESP}"
echo
[[ "${HTTP}" == "200" ]] || exit 1

JOB_ID="$(python3 -c "import json; d=json.load(open('${RESP}')); print(d.get('job',{}).get('job_id',''))")"
TPL_ID="$(python3 -c "import json; d=json.load(open('${RESP}')); print(d.get('job',{}).get('template_id',''))")"
echo "[m3] job_id=${JOB_ID} template_id=${TPL_ID}"

deadline=$((SECONDS + JOB_TIMEOUT_SEC))
while (( SECONDS < deadline )); do
  OUT="$(sudo ${CUBEMASTERCLI} --address 127.0.0.1 --port 8089 tpl status --job-id "${JOB_ID}" 2>&1)" || true
  echo "${OUT}"
  ST="$(echo "${OUT}" | sed -n 's/^.*status: //p' | head -1 | tr -d '[:space:]')"
  case "${ST}" in
    READY) echo "[m3] TEMPLATE READY"; exit 0 ;;
    FAILED) echo "[m3] TEMPLATE FAILED"; exit 1 ;;
  esac
  sleep 15
done
echo "[m3] timeout"
exit 1
