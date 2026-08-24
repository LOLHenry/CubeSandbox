#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build unified offline tarball for Kunpeng: replication kit + inner envd offline kit.
#
# Run on networked aarch64 builder (or GHA ubuntu-24.04-arm).
#
#   ./deploy/agr-mobile-replication-kit/scripts/build-unified-tarball.sh
#
# Output:
#   deploy/agr-mobile-replication-kit/dist/agr-mobile-replication-kit-kunpeng-arm64.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
DIST="${ROOT}/dist"
STAGING="${DIST}/staging"
INNER_RELEASE_TAG="${INNER_RELEASE_TAG:-agr-mobile-replication-kit-inner}"
OUT_NAME="agr-mobile-replication-kit-kunpeng-arm64"

log() { echo "==> $*"; }

rm -rf "$STAGING"
mkdir -p "$STAGING/$OUT_NAME" "$DIST"

log "Build inner envd offline kit"
RELEASE_TAG="$INNER_RELEASE_TAG" INCLUDE_REDROID=1 \
  "${ROOT}/scripts/01-build-offline-kit.sh"

INNER_TAR="$(ls -1 "${REPO_ROOT}/deploy/sandbox-images/sandbox-android-redroid-envd/offline-build-kit/dist/${INNER_RELEASE_TAG}"*.tar.gz 2>/dev/null | head -1)"
[[ -n "$INNER_TAR" ]] || { echo "inner tarball not found" >&2; exit 1; }

log "Stage replication kit files"
rsync -a \
  --exclude dist \
  --exclude '.git' \
  "$ROOT/" "$STAGING/$OUT_NAME/"

mkdir -p "$STAGING/$OUT_NAME/inner-kit"
tar xzf "$INNER_TAR" -C "$STAGING/$OUT_NAME/inner-kit" --strip-components=1

chmod +x "$STAGING/$OUT_NAME/scripts/"*.sh "$STAGING/$OUT_NAME/probe/"*.sh 2>/dev/null || true
cp "$ROOT/configs/env.kunpeng.example" "$STAGING/$OUT_NAME/.env.example"

log "Write bundle manifest"
python3 - <<'PY' "$ROOT/MANIFEST.json" "$STAGING/$OUT_NAME/BUNDLE_MANIFEST.json" "$INNER_TAR"
import json, sys, hashlib, pathlib
src, dst, inner = sys.argv[1:4]
m = json.load(open(src))
h = hashlib.sha256()
with open(inner, 'rb') as f:
    for chunk in iter(lambda: f.read(1<<20), b''):
        h.update(chunk)
m['bundle'] = {
    'inner_tarball': pathlib.Path(inner).name,
    'inner_sha256': h.hexdigest(),
    'unified_name': 'agr-mobile-replication-kit-kunpeng-arm64.tar.gz'
}
json.dump(m, open(dst, 'w'), indent=2)
PY

log "Create unified tarball"
tar czf "${DIST}/${OUT_NAME}.tar.gz" -C "$STAGING" "$OUT_NAME"
sha256sum "${DIST}/${OUT_NAME}.tar.gz" > "${DIST}/${OUT_NAME}.tar.gz.sha256"

log "Done: ${DIST}/${OUT_NAME}.tar.gz"
cat "${DIST}/${OUT_NAME}.tar.gz.sha256"
