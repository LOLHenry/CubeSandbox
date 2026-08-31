#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate multirun JSON using the distributed ext4 artifact (not OCI image name).
#
# After: cubemastercli tpl create-from-image ...  →  artifact_id=rfs-...
# Usage:
#   ./generate-cold-multirun-json.sh rfs-cbaa3e6bb0fdfe4e91e06fe8
#   ./generate-cold-multirun-json.sh --from-job d7d8aed8-0bfe-4cd9-bef8-6a10410e92ad
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX="${CUBE_TOOLBOX:-/usr/local/services/cubetoolbox}"
ARTIFACT_ID=""
JOB_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-job) JOB_ID="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    rfs-*|artifact-*) ARTIFACT_ID="$1"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "${JOB_ID}" ]]; then
  command -v cubemastercli >/dev/null || { echo "cubemastercli required for --from-job" >&2; exit 1; }
  OUT="$(cubemastercli tpl image-job --job-id "${JOB_ID}" 2>/dev/null || cubemastercli tpl status --job-id "${JOB_ID}" 2>/dev/null || true)"
  ARTIFACT_ID="$(printf '%s\n' "$OUT" | sed -n 's/^artifact_id:[[:space:]]*//p; s/"artifact_id"[[:space:]]*:[[:space:]]*"\(rfs-[^"]*\)".*/\1/p' | head -1)"
fi

[[ -n "${ARTIFACT_ID}" ]] || {
  echo "Usage: $0 <artifact-id>" >&2
  echo "       $0 --from-job <job-id>" >&2
  exit 1
}

PMEM="${TOOLBOX}/cubebox_os_image/${ARTIFACT_ID}/${ARTIFACT_ID}.ext4"
if [[ ! -f "${PMEM}" ]]; then
  echo "WARN: ${PMEM} not found on this node (check: find ${TOOLBOX}/cubebox_os_image -name '*.ext4')"
else
  ls -lh "${PMEM}"
fi

OUT_JSON="${SCRIPT_DIR}/examples/redroid-cold-fd-sanitize-${ARTIFACT_ID}.json"
mkdir -p "${SCRIPT_DIR}/examples"
sed "s|\"image\": \"sandbox-android-redroid-cube:16.0.0-arm64\"|\"image\": \"${ARTIFACT_ID}\"|" \
  "${SCRIPT_DIR}/examples/redroid-cold-fd-sanitize.json" > "${OUT_JSON}"

echo "OK: ${OUT_JSON}"
echo "Run: cubemastercli multirun --norm ${OUT_JSON}"
