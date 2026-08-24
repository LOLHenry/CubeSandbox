#!/usr/bin/env bash
# Build envd + envd-starter binaries (GOOS=android) without network.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${GO_INSTALL_DIR:-/usr/local}/go/bin:${PATH}"
export GOPROXY=off
export GOSUMDB=off

command -v go >/dev/null || { echo "Run ./scripts/01-install-go.sh first" >&2; exit 1; }

INFRA_COMMIT="$(cat "${KIT_ROOT}/src/infra.commit")"
COMMIT_SHA="${INFRA_COMMIT:0:12}"
OUT_DIR="${KIT_ROOT}/out"
mkdir -p "${OUT_DIR}"

echo "==> Building envd (android/arm64, vendored)"
cd "${KIT_ROOT}/src/infra/packages/envd"
export GOWORK=off
CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
  go build -buildvcs=false -mod=vendor -a \
    -ldflags "-X=main.commitSHA=${COMMIT_SHA} -s -w" \
    -o "${OUT_DIR}/envd" .

echo "==> Building envd-starter (android/arm64)"
cd "${KIT_ROOT}/src/envd-starter"
CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
  go build -buildvcs=false -a -ldflags "-s -w" -o "${OUT_DIR}/envd-starter" .

echo "==> Verifying ELF"
file "${OUT_DIR}/envd" "${OUT_DIR}/envd-starter"
if file "${OUT_DIR}/envd" | grep -q 'statically linked'; then
  echo "ERROR: envd looks like GOOS=linux static binary; expected Android linker64" >&2
  exit 1
fi
if ! file "${OUT_DIR}/envd" | grep -q 'interpreter /system/bin/linker64'; then
  echo "ERROR: envd is not Android/bionic ELF" >&2
  exit 1
fi

echo "OK: binaries in ${OUT_DIR}/"
ls -lh "${OUT_DIR}/envd" "${OUT_DIR}/envd-starter"
