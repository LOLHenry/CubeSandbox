#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# End-to-end: build/load Android envd image → create CubeSandbox template → wait READY.
# Run on Kunpeng host with KVM + CubeSandbox one-click (euler-arm-199 class).
#
# Usage:
#   # Build image locally, create template (120s probe via HTTP API):
#   BUILD_IMAGE=1 ./e2e-template-ready.sh
#
#   # Load offline bundle then test:
#   BUNDLE_TAR=/path/to/cube-sandbox-android-kunpeng-arm64-envd-docker-envd-preview12.tar.gz \
#     ./e2e-template-ready.sh
#
#   # Re-test image already in docker:
#   ./e2e-template-ready.sh
#
# Environment:
#   CUBEMASTER_ADDR     default 127.0.0.1:8089
#   CUBEMASTERCLI       path to cubemastercli (default: cubemastercli in PATH)
#   IMAGE               default sandbox-android-redroid-envd:16.0.0-arm64
#   PROBE_TIMEOUT_MS    default 120000
#   CPU_MILLICORES      default 4000
#   MEMORY_MIB          default 6144
#   BUILD_IMAGE=1       run deploy/sandbox-images/.../build.sh first
#   BUNDLE_TAR          gunzip|docker load before template create
#   SKIP_ELF_CHECK=1    skip verify-android-envd-image.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

IMAGE="${IMAGE:-sandbox-android-redroid-envd:16.0.0-arm64}"
CUBEMASTER_ADDR="${CUBEMASTER_ADDR:-127.0.0.1:8089}"
CUBEMASTERCLI="${CUBEMASTERCLI:-cubemastercli}"
PROBE_TIMEOUT_MS="${PROBE_TIMEOUT_MS:-120000}"
CPU_MILLICORES="${CPU_MILLICORES:-4000}"
MEMORY_MIB="${MEMORY_MIB:-6144}"
WRITABLE_LAYER_SIZE="${WRITABLE_LAYER_SIZE:-10Gi}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-10}"
JOB_TIMEOUT_SEC="${JOB_TIMEOUT_SEC:-900}"

TEMPLATE_ID=""
JOB_ID=""
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/android-envd-e2e-$$}"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

check_prerequisites() {
  require_cmd docker
  require_cmd curl
  require_cmd "${CUBEMASTERCLI}"
  [[ -e /dev/kvm ]] || die "/dev/kvm missing — template create requires KVM"
  docker info >/dev/null 2>&1 || die "docker daemon not running"
  if ! curl -sf "http://${CUBEMASTER_ADDR}/health" >/dev/null 2>&1; then
    if ! curl -sf "http://${CUBEMASTER_ADDR}/" >/dev/null 2>&1; then
      log "WARN: cubemaster http://${CUBEMASTER_ADDR} not reachable (continuing anyway)"
    fi
  fi
}

load_bundle() {
  local tar="$1"
  [[ -f "${tar}" ]] || die "bundle not found: ${tar}"
  log "loading bundle ${tar}"
  gunzip -c "${tar}" | docker load
}

build_image() {
  log "building image ${IMAGE}"
  TAG="${IMAGE##*:}" IMAGE_TAG="${IMAGE##*:}" "${SCRIPT_DIR}/build.sh"
}

ensure_image() {
  if [[ "${BUILD_IMAGE:-0}" == "1" ]]; then
    build_image
  fi
  if [[ -n "${BUNDLE_TAR:-}" ]]; then
    load_bundle "${BUNDLE_TAR}"
  fi
  docker image inspect "${IMAGE}" >/dev/null 2>&1 || die "image not found: ${IMAGE} (set BUILD_IMAGE=1 or BUNDLE_TAR=...)"
  if [[ "${SKIP_ELF_CHECK:-0}" != "1" ]]; then
    "${SCRIPT_DIR}/lib/verify-android-envd-image.sh" "${IMAGE}"
  fi
  local ep
  ep="$(docker image inspect "${IMAGE}" --format '{{json .Config.Entrypoint}}')"
  log "image entrypoint=${ep}"
}

new_request_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

submit_template_job() {
  local request_id
  request_id="$(new_request_id)"
  log "submitting template from-image (probe_timeout_ms=${PROBE_TIMEOUT_MS}) requestID=${request_id}"

  local body_file resp_file
  body_file="$(mktemp)"
  resp_file="$(mktemp)"
  trap 'rm -f "${body_file}" "${resp_file}"' RETURN

  cat >"${body_file}" <<EOF
{
  "requestID": "${request_id}",
  "source_image_ref": "${IMAGE}",
  "writable_layer_size": "${WRITABLE_LAYER_SIZE}",
  "exposed_ports": [5555, 49983],
  "container_overrides": {
    "resources": {
      "cpu": "${CPU_MILLICORES}m",
      "mem": "${MEMORY_MIB}Mi"
    },
    "probe": {
      "probe_handler": {
        "http_get": {
          "path": "/health",
          "port": 49983,
          "host": ""
        }
      },
      "timeout_ms": ${PROBE_TIMEOUT_MS},
      "period_ms": 500,
      "failure_threshold": 240,
      "success_threshold": 1
    }
  }
}
EOF

  local http_code
  http_code="$(curl -sS -o "${resp_file}" -w '%{http_code}' \
    -X POST "http://${CUBEMASTER_ADDR}/cube/template/from-image" \
    -H 'Content-Type: application/json' \
    --data-binary @"${body_file}")"

  log "create-from-image HTTP ${http_code}"
  cat "${resp_file}"
  echo ""

  [[ "${http_code}" == "200" ]] || die "create-from-image failed HTTP ${http_code}"

  if command -v python3 >/dev/null 2>&1; then
    JOB_ID="$(python3 -c "import json,sys; d=json.load(open('${resp_file}')); print(d.get('job',{}).get('job_id',''))")"
    TEMPLATE_ID="$(python3 -c "import json,sys; d=json.load(open('${resp_file}')); print(d.get('job',{}).get('template_id',''))")"
  else
    JOB_ID="$(sed -n 's/.*"job_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${resp_file}" | head -1)"
    TEMPLATE_ID="$(sed -n 's/.*"template_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${resp_file}" | head -1)"
  fi

  [[ -n "${JOB_ID}" ]] || die "empty job_id in response"
  [[ -n "${TEMPLATE_ID}" ]] || die "empty template_id in response"
  log "job_id=${JOB_ID} template_id=${TEMPLATE_ID}"
}

wait_for_job() {
  local deadline=$((SECONDS + JOB_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    local out status
    out="$("${CUBEMASTERCLI}" --address "${CUBEMASTER_ADDR%%:*}" --port "${CUBEMASTER_ADDR##*:}" \
      tpl status --job-id "${JOB_ID}" 2>&1)" || true
    echo "${out}"
    status="$(echo "${out}" | sed -n 's/^.*status: //p' | head -1 | tr -d '[:space:]')"
  case "${status}" in
      READY)
        log "SUCCESS: template ${TEMPLATE_ID} READY"
        return 0
        ;;
      FAILED)
        log "FAILED: template job failed"
        collect_diagnostics
        return 1
        ;;
      *)
        sleep "${POLL_INTERVAL_SEC}"
        ;;
    esac
  done
  log "TIMEOUT: job ${JOB_ID} not terminal after ${JOB_TIMEOUT_SEC}s"
  collect_diagnostics
  return 1
}

collect_diagnostics() {
  mkdir -p "${ARTIFACT_DIR}"
  local sid="${TEMPLATE_ID}_0"
  log "collecting diagnostics → ${ARTIFACT_DIR}"

  {
    echo "job_id=${JOB_ID}"
    echo "template_id=${TEMPLATE_ID}"
    echo "image=${IMAGE}"
    echo "probe_timeout_ms=${PROBE_TIMEOUT_MS}"
  } >"${ARTIFACT_DIR}/meta.txt"

  "${CUBEMASTERCLI}" --address "${CUBEMASTER_ADDR%%:*}" --port "${CUBEMASTER_ADDR##*:}" \
    tpl status --job-id "${JOB_ID}" >"${ARTIFACT_DIR}/job-status.txt" 2>&1 || true

  if [[ -d "/data/log/template/${sid}" ]]; then
    cp -a "/data/log/template/${sid}/." "${ARTIFACT_DIR}/template-logs/" 2>/dev/null || true
  fi

  if command -v cubecli >/dev/null 2>&1; then
    cubecli logs --tpl --all --stderr "${TEMPLATE_ID}" >"${ARTIFACT_DIR}/cubecli-stderr.txt" 2>&1 || true
    cubecli logs --tpl --all "${TEMPLATE_ID}" >"${ARTIFACT_DIR}/cubecli-stdout.txt" 2>&1 || true
  fi

  if [[ -f /data/log/Cubelet/Cubelet-req.log ]]; then
    grep -a "${TEMPLATE_ID}" /data/log/Cubelet/Cubelet-req.log | tail -80 >"${ARTIFACT_DIR}/cubelet-req-tail.txt" 2>/dev/null || true
  fi
  if [[ -f /data/log/CubeShim/cube-shim-req.log ]]; then
    grep -a "${sid}" /data/log/CubeShim/cube-shim-req.log | tail -80 >"${ARTIFACT_DIR}/cubeshim-tail.txt" 2>/dev/null || true
  fi

  log "diagnostics saved under ${ARTIFACT_DIR}"
  ls -la "${ARTIFACT_DIR}" 2>/dev/null || true
}

main() {
  check_prerequisites
  ensure_image
  submit_template_job
  wait_for_job
}

main "$@"
