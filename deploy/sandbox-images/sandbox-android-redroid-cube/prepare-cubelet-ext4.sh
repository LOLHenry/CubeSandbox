#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build & distribute ext4 from sandbox-android-redroid-cube Docker image via
# cubemastercli tpl create-from-image. Then generate multirun JSON keyed by
# artifact_id (rfs-...), NOT the Docker tag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-sandbox-android-redroid-cube:16.0.0-arm64}"
WRITABLE="${WRITABLE:-10Gi}"
CPU="${CPU:-4000}"
MEMORY="${MEMORY:-6144}"
EXPOSE_PORT="${EXPOSE_PORT:-5555}"
NATIVE_ENV="${NATIVE_ENV:-/usr/local/services/cubetoolbox/.one-click.env}"
TOOLBOX="${CUBE_TOOLBOX:-/usr/local/services/cubetoolbox}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker required"
command -v cubemastercli >/dev/null || die "cubemastercli required"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "==> Docker image ${IMAGE} missing; building..."
  "${SCRIPT_DIR}/build-docker-image.sh"
fi

ARCH="$(docker image inspect "${IMAGE}" --format '{{.Architecture}}')"
[[ "${ARCH}" == "arm64" ]] || die "${IMAGE} is ${ARCH}, need arm64"
echo "==> Docker OK: arch=${ARCH} entrypoint=$(docker image inspect "${IMAGE}" --format '{{json .Config.Entrypoint}}')"

if [[ -f "${NATIVE_ENV}" ]] && ! grep -q '^CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false' "${NATIVE_ENV}" 2>/dev/null; then
  echo "WARN: set CUBEMASTER_NATIVE_ROOTFS_EXPORT_ENABLED=false in ${NATIVE_ENV} (README_KUNPENG §2.0)"
fi

echo "==> Building & distributing ext4 via cubemastercli tpl create-from-image"

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
ARTIFACT_ID="$(sed -n 's/^artifact_id:[[:space:]]*//p' "${JOB_OUT}" | head -1)"
rm -f "${JOB_OUT}"

[[ -n "${JOB_ID}" ]] || die "could not parse job_id"
echo "==> Watching job ${JOB_ID} (template ${TPL_ID:-?} artifact ${ARTIFACT_ID:-?})"
cubemastercli tpl watch --job-id "${JOB_ID}"

[[ -n "${ARTIFACT_ID}" ]] || ARTIFACT_ID="$(cubemastercli tpl image-job --job-id "${JOB_ID}" 2>/dev/null | sed -n 's/^artifact_id:[[:space:]]*//p' | head -1 || true)"
[[ -n "${ARTIFACT_ID}" ]] || die "could not determine artifact_id; use: cubemastercli tpl image-job --job-id ${JOB_ID}"

PMEM="${TOOLBOX}/cubebox_os_image/${ARTIFACT_ID}/${ARTIFACT_ID}.ext4"
if [[ -f "${PMEM}" ]]; then
  echo "OK: ext4 at ${PMEM}"
  ls -lh "${PMEM}"
else
  echo "WARN: ${PMEM} missing; try: find ${TOOLBOX}/cubebox_os_image -name '*.ext4'"
fi

chmod +x "${SCRIPT_DIR}/generate-cold-multirun-json.sh"
"${SCRIPT_DIR}/generate-cold-multirun-json.sh" "${ARTIFACT_ID}"

echo ""
echo "Do NOT use examples/redroid-cold-fd-sanitize.json directly (Docker tag != artifact id)."
echo "Use the generated JSON from generate-cold-multirun-json.sh above."
