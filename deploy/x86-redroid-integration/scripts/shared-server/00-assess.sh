#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Read-only environment assessment for CubeSandbox + ReDroid on a shared server.
# Touches only: writes report under ${WORK_ROOT} (default ~/cube-redroid-work).
# Does NOT read other users' home dirs or modify system config/libs.
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-${HOME}/cube-redroid-work}"
REPORT="${WORK_ROOT}/assess-report.txt"
JSON="${WORK_ROOT}/assess-report.json"

log() { printf '[assess] %s\n' "$*"; }
section() { printf '\n=== %s ===\n' "$*"; }

mkdir -p "${WORK_ROOT}"
: > "${REPORT}"

run_check() {
  local name="$1" status="$2" detail="$3"
  printf '%s\t%s\t%s\n' "${name}" "${status}" "${detail}" | tee -a "${REPORT}"
}

section "Identity"
log "user=$(whoami) home=${HOME} work_root=${WORK_ROOT}"
run_check "user" "INFO" "$(whoami)"
run_check "home" "INFO" "${HOME}"
[[ "${HOME}" == /home/fangyu* || "$(whoami)" == "fangyu" ]] && run_check "home_scope" "PASS" "running as fangyu" || run_check "home_scope" "WARN" "not fangyu — adjust WORK_ROOT manually"

section "CPU / arch"
ARCH="$(uname -m)"
run_check "arch" "INFO" "${ARCH}"
nproc_val="$(nproc 2>/dev/null || echo 0)"
run_check "cpu_cores" "INFO" "${nproc_val}"
grep -m1 'model name' /proc/cpuinfo 2>/dev/null | tee -a "${REPORT}" || true

section "Memory / disk (home only)"
free -h | tee -a "${REPORT}"
avail_mb="$(df -BM "${HOME}" 2>/dev/null | awk 'NR==2{gsub(/M/,"",$4); print $4}')"
run_check "home_free_mb" "INFO" "${avail_mb:-unknown}"
if [[ "${avail_mb:-0}" -ge 81920 ]]; then
  run_check "home_disk" "PASS" ">=80GB free in ${HOME}"
elif [[ "${avail_mb:-0}" -ge 40960 ]]; then
  run_check "home_disk" "WARN" "40-80GB free — tight for VM+images"
else
  run_check "home_disk" "FAIL" "<40GB free in ${HOME}"
fi
mem_avail_mb="$(free -m | awk '/^Mem:/{print $7}')"
run_check "mem_available_mb" "INFO" "${mem_avail_mb}"
if [[ "${mem_avail_mb:-0}" -ge 16384 ]]; then
  run_check "memory" "PASS" ">=16GB available"
elif [[ "${mem_avail_mb:-0}" -ge 8192 ]]; then
  run_check "memory" "WARN" "8-16GB — VM needs VM_MEMORY_MB=8192 min"
else
  run_check "memory" "FAIL" "<8GB available"
fi

section "Virtualization"
if [[ -e /dev/kvm ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    run_check "kvm" "PASS" "/dev/kvm rw"
  elif groups 2>/dev/null | grep -q kvm; then
    run_check "kvm" "WARN" "/dev/kvm exists but not rw — may need: sudo chmod 666 /dev/kvm (ask admin)"
  else
    run_check "kvm" "WARN" "/dev/kvm exists, not rw, user not in kvm group"
  fi
else
  run_check "kvm" "FAIL" "no /dev/kvm"
fi
if grep -q hypervisor /proc/cpuinfo 2>/dev/null; then
  run_check "nested" "WARN" "CPU hypervisor flag set — nested virt; prefer bare-metal if slow"
else
  run_check "nested" "PASS" "no hypervisor flag (likely bare metal or PV)"
fi

section "Android / ReDroid kernel modules"
if [[ -e /dev/binder || -e /dev/binderfs ]]; then
  run_check "binder" "PASS" "binder device present"
elif grep -q binder /proc/filesystems 2>/dev/null; then
  run_check "binder" "WARN" "binder in /proc/filesystems — modprobe binder_linux may work"
else
  run_check "binder" "WARN" "no binder — M1 on host needs module; OK inside dev-env VM"
fi
if [[ -e /dev/ashmem ]] || grep -q ashmem /proc/misc 2>/dev/null; then
  run_check "ashmem" "PASS" "ashmem available"
else
  run_check "ashmem" "WARN" "no ashmem — may compile redroid-modules for M1"
fi

section "Tools (read-only PATH check)"
need_ok=0
for cmd in curl docker git python3 qemu-system-x86_64; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    run_check "cmd_${cmd}" "PASS" "$(command -v "${cmd}")"
  else
    if [[ "${cmd}" == "qemu-system-x86_64" && "${ARCH}" == "aarch64" ]]; then
      if command -v qemu-system-aarch64 >/dev/null 2>&1; then
        run_check "cmd_qemu-system-aarch64" "PASS" "$(command -v qemu-system-aarch64)"
      else
        run_check "cmd_${cmd}" "FAIL" "missing"
        need_ok=1
      fi
    else
      run_check "cmd_${cmd}" "FAIL" "missing"
      need_ok=1
    fi
  fi
done
if docker info >/dev/null 2>&1; then
  run_check "docker_daemon" "PASS" "docker accessible"
  docker info 2>/dev/null | grep -E 'Architecture|CPUs|Total Memory' | tee -a "${REPORT}" || true
else
  run_check "docker_daemon" "FAIL" "docker not usable by $(whoami)"
fi

section "Platform recommendation"
case "${ARCH}" in
  x86_64|amd64)
    run_check "platform" "PASS" "x86_64 — use x86-redroid-integration amd64 path"
    ;;
  aarch64|arm64)
    run_check "platform" "WARN" "aarch64 — use arm64 ReDroid/envd (not amd64 VM); x86 QEMU emulation impractical"
    ;;
  *)
    run_check "platform" "FAIL" "unsupported arch ${ARCH}"
    ;;
esac

section "Verdict"
fail_count="$(grep -c $'\tFAIL\t' "${REPORT}" || true)"
warn_count="$(grep -c $'\tWARN\t' "${REPORT}" || true)"
if [[ "${fail_count}" -eq 0 && "${ARCH}" == "x86_64" ]]; then
  run_check "verdict" "PASS" "likely OK for full deploy in ${WORK_ROOT} (dev-env VM isolates one-click)"
  exit_code=0
elif [[ "${fail_count}" -eq 0 && "${ARCH}" == "aarch64" ]]; then
  run_check "verdict" "WARN" "ARM host — deploy arm64 Cube+ReDroid natively, not x86 dev-env VM"
  exit_code=0
else
  run_check "verdict" "FAIL" "${fail_count} hard failures — see report"
  exit_code=1
fi

# minimal JSON for automation
{
  printf '{'
  printf '"user":"%s",' "$(whoami)"
  printf '"arch":"%s",' "${ARCH}"
  printf '"work_root":"%s",' "${WORK_ROOT}"
  printf '"fail":%s,' "${fail_count}"
  printf '"warn":%s,' "${warn_count}"
  printf '"report":"%s"' "${REPORT}"
  printf '}\n'
} > "${JSON}"

log "report: ${REPORT}"
log "json:   ${JSON}"
exit "${exit_code}"
