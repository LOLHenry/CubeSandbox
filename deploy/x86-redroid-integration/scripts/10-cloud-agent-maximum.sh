#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Cloud Agent: run maximum achievable pipeline (M0 guest + M2 + M3 artifact).
#
# Cloud Agent limits (verified):
#   - Host has /dev/kvm but systemd is not PID 1 → one-click on host fails
#   - Outer VM with USE_TCG=0 (KVM) does not boot SSH on this environment
#   - Inner CubeVM (M3 CREATING_TEMPLATE, M1 ReDroid) → VmExit::Reset under TCG nest
#   - M0 control plane + M2 image + M3 artifact (through DISTRIBUTING) DO work
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VM_MEMORY_MB="${VM_MEMORY_MB:-8192}"
USE_TCG="${USE_TCG:-1}"

log() { printf '[cloud-agent] %s\n' "$*"; }
warn() { log "WARN: $*"; }
die() { log "ERROR: $*"; exit 1; }

section() { log "======== $* ========"; }

section "M0 — dev-env VM + one-click (guest)"
[[ -e /dev/kvm ]] && sudo chmod 666 /dev/kvm 2>/dev/null || true
if ! curl -sf http://127.0.0.1:13000/health >/dev/null 2>&1; then
  log "starting VM USE_TCG=${USE_TCG}"
  USE_TCG="${USE_TCG}" VM_MEMORY_MB="${VM_MEMORY_MB}" \
    bash "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/run-dev-vm-ovmf.sh"
  for _ in $(seq 1 40); do
    curl -sf http://127.0.0.1:13000/health >/dev/null 2>&1 && break
    sleep 15
  done
fi
curl -sf http://127.0.0.1:13000/health | tee /tmp/cloud-agent-m0-health.json
log "M0 OK"

section "M2 — amd64 envd image on host"
if ! docker image inspect sandbox-android-redroid-envd:16.0.0-amd64 >/dev/null 2>&1; then
  DIST="${REPO_ROOT}/deploy/x86-redroid-integration/dist"
  mkdir -p "${DIST}"
  if [[ ! -f "${DIST}/cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz" ]]; then
    log "download GitHub Release bundle"
    gh release download x86-redroid-amd64-envd-m2-preview -D "${DIST}" \
      -p 'cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz*' \
      || die "download release failed"
  fi
  ( cd "${DIST}" && sha256sum -c cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz.sha256 )
  gunzip -c "${DIST}/cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz" | docker load
fi
docker image inspect sandbox-android-redroid-envd:16.0.0-amd64 --format 'M2 {{.Architecture}} {{.Id}}'
log "M2 OK"

section "M3 — import + template artifact (guest)"
CUBECLI_TIMEOUT=30m JOB_TIMEOUT_SEC=3600 \
  bash "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/08-guest-e2e-template.sh" \
  && M3=OK || M3=PARTIAL

if [[ "${M3:-}" == "OK" ]]; then
  log "M3 full READY"
else
  warn "M3 did not reach READY (expected on Cloud Agent: CubeVM VmExit::Reset at CREATING_TEMPLATE)"
fi

section "M1 — ReDroid standalone (guest, best-effort)"
TIMEOUT=900 bash "${REPO_ROOT}/deploy/x86-redroid-integration/scripts/06-guest-verify-redroid.sh" \
  && M1=OK || M1=FAIL

if [[ "${M1:-}" == "OK" ]]; then
  log "M1 OK"
else
  warn "M1 failed (expected on Cloud Agent: Android init property area under nested TCG)"
fi

section "Summary"
log "M0: OK | M2: OK | M3 artifact: ${M3:-PARTIAL} | M1: ${M1:-FAIL}"
log "CubeAPI http://127.0.0.1:13000/health | SSH :10022"
