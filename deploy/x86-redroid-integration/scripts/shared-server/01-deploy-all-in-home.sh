#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Full CubeSandbox + ReDroid deploy for shared server — ALL artifacts under WORK_ROOT.
#
# Constraints honored:
#   - Default WORK_ROOT=~/cube-redroid-work (only writes under $HOME)
#   - Does not modify system env files, ldconfig, or other users' dirs
#   - One-click installs run INSIDE an isolated dev-env VM (qcow2 in WORK_ROOT)
#
# Usage (on the server as fangyu):
#   bash 01-deploy-all-in-home.sh
#   WORK_ROOT=~/cube-redroid-work BRANCH=cursor/x86-redroid-integration-5222 bash 01-deploy-all-in-home.sh
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-${HOME}/cube-redroid-work}"
REPO_DIR="${REPO_DIR:-${WORK_ROOT}/CubeSandbox}"
BRANCH="${BRANCH:-cursor/x86-redroid-integration-5222}"
VM_MEMORY_MB="${VM_MEMORY_MB:-8192}"
USE_TCG="${USE_TCG:-auto}"
SKIP_CLONE="${SKIP_CLONE:-0}"
SKIP_M2_BUILD="${SKIP_M2_BUILD:-1}"
RELEASE_TAG="${RELEASE_TAG:-x86-redroid-amd64-envd-m2-preview}"

log() { printf '[deploy-home] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

[[ "$(whoami)" == "fangyu" ]] || die "run as fangyu only (shared server policy)"
[[ "${WORK_ROOT}" == "${HOME}"* ]] || die "WORK_ROOT must be under HOME (${HOME})"
mkdir -p "${WORK_ROOT}"

cd "${WORK_ROOT}"

if [[ "${SKIP_CLONE}" != "1" ]]; then
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log "clone CubeSandbox → ${REPO_DIR}"
    git clone --depth 1 --branch "${BRANCH}" https://github.com/LOLHenry/CubeSandbox.git "${REPO_DIR}" \
      || git clone --depth 1 https://github.com/LOLHenry/CubeSandbox.git "${REPO_DIR}"
    cd "${REPO_DIR}" && git fetch origin "${BRANCH}" && git checkout "${BRANCH}" 2>/dev/null || true
  else
    log "update ${REPO_DIR}"
    cd "${REPO_DIR}" && git fetch origin "${BRANCH}" && git checkout "${BRANCH}" && git pull --ff-only origin "${BRANCH}" || true
  fi
fi
cd "${REPO_DIR}"

log "assessment"
bash deploy/x86-redroid-integration/scripts/shared-server/00-assess.sh || true

ARCH="$(uname -m)"
[[ "${ARCH}" == "x86_64" ]] || die "this script targets x86_64 hosts; for aarch64 use arm64 catalog path"

[[ -e /dev/kvm ]] || die "no /dev/kvm — cannot run CubeVM"
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  :
else
  log "WARN: /dev/kvm not rw — trying without sudo (if fail, ask admin: usermod -aG kvm fangyu)"
fi

command -v docker >/dev/null || die "docker not in PATH"
docker info >/dev/null 2>&1 || die "docker not usable"

# M2: prefer GitHub Release over local build (no NDK toolchain in home)
if [[ "${SKIP_M2_BUILD}" == "1" ]]; then
  DIST="${WORK_ROOT}/dist"
  mkdir -p "${DIST}"
  if ! docker image inspect sandbox-android-redroid-envd:16.0.0-amd64 >/dev/null 2>&1; then
    log "download M2 offline bundle from GitHub Release"
    if command -v gh >/dev/null 2>&1; then
      gh release download "${RELEASE_TAG}" -D "${DIST}" -p 'cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz*'
    else
      curl -fsSL -o "${DIST}/bundle.tar.gz" \
        "https://github.com/LOLHenry/CubeSandbox/releases/download/${RELEASE_TAG}/cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz"
      curl -fsSL -o "${DIST}/bundle.tar.gz.sha256" \
        "https://github.com/LOLHenry/CubeSandbox/releases/download/${RELEASE_TAG}/cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz.sha256"
    fi
    ( cd "${DIST}" && sha256sum -c cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz.sha256 )
    gunzip -c "${DIST}/cube-sandbox-android-x86-amd64-envd-docker-m2-preview.tar.gz" | docker load
  fi
  docker image inspect sandbox-android-redroid-envd:16.0.0-amd64 >/dev/null
  log "M2 image ready"
else
  bash deploy/x86-redroid-integration/scripts/07-build-amd64-redroid-envd.sh
fi

# Dev-env VM entirely under WORK_ROOT
export DEV_ENV_WORK="${WORK_ROOT}/dev-env-work"
mkdir -p "${DEV_ENV_WORK}"
ln -sfn "${REPO_DIR}/dev-env" "${WORK_ROOT}/dev-env-link" 2>/dev/null || true

# Prepare qcow2 if missing
QCOW2="${DEV_ENV_WORK}/OpenCloudOS-GenericCloud-9.6-20260514.2.x86_64.qcow2"
if [[ ! -f "${QCOW2}" ]]; then
  log "download OpenCloudOS dev-env image (~1.5GB) to ${DEV_ENV_WORK}"
  mkdir -p "${DEV_ENV_WORK}"
  curl -fsSL -o "${QCOW2}.partial" \
    "https://cloud-images.openeuler.org/opencloudos/9/x86_64/OpenCloudOS-GenericCloud-9.6-20260514.2.x86_64.qcow2" \
    || curl -fsSL -o "${QCOW2}.partial" \
    "https://mirrors.aliyun.com/opencloudos/9/images/x86_64/OpenCloudOS-GenericCloud-9.6-20260514.2.x86_64.qcow2" \
    || die "download qcow2 failed — place image manually at ${QCOW2}"
  mv "${QCOW2}.partial" "${QCOW2}"
fi

# Wire dev-env scripts to use WORK_ROOT paths
export WORK_DIR="${DEV_ENV_WORK}"
export REPO_ROOT="${REPO_DIR}"

if [[ "${USE_TCG}" == "auto" ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]] && timeout 3 qemu-system-x86_64 -enable-kvm -machine q35 -accel kvm -cpu host -m 64 -display none -serial none 2>/dev/null; then
    USE_TCG=0
  else
    USE_TCG=1
  fi
fi
log "USE_TCG=${USE_TCG} VM_MEMORY_MB=${VM_MEMORY_MB}"

log "M0: provision dev-env VM + one-click inside guest"
USE_TCG="${USE_TCG}" VM_MEMORY_MB="${VM_MEMORY_MB}" WORK_DIR="${WORK_DIR}" \
  bash deploy/x86-redroid-integration/scripts/03-dev-env-provision-and-install.sh

log "M1: ReDroid + adb in guest"
TIMEOUT=900 bash deploy/x86-redroid-integration/scripts/06-guest-verify-redroid.sh || log "M1 failed (see guest logs)"

log "M3: template E2E in guest"
CUBECLI_TIMEOUT=30m JOB_TIMEOUT_SEC=3600 \
  bash deploy/x86-redroid-integration/scripts/08-guest-e2e-template.sh || log "M3 failed (see guest logs)"

log "DONE — logs under ${WORK_ROOT}; CubeAPI host port :13000 SSH :10022"
curl -sf http://127.0.0.1:13000/health && log "host health OK" || log "health check failed"
