#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="${SCRIPT_DIR}/../assets/sandbox-catalog/sandbox-android-kunpeng-arm64-envd.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${CATALOG}" ]] || fail "missing catalog file: ${CATALOG}"

python3 - "${CATALOG}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if data["id"] != "sandbox-android-kunpeng-arm64-envd":
    raise SystemExit(f"unexpected id: {data['id']}")
if data["instance_type"] != "cubebox":
    raise SystemExit(f"unexpected instance_type: {data['instance_type']}")
if not data["workload"].get("envd", {}).get("enabled"):
    raise SystemExit("workload.envd.enabled must be true")
published = data["workload"].get("published_images", {})
for reg in ("cn", "intl"):
    if "sandbox-android-redroid-envd:16.0.0-arm64" not in published[reg]:
        raise SystemExit(f"unexpected published image for {reg}")
if data["template_defaults"].get("probe_port") != 49983:
    raise SystemExit("template_defaults.probe_port must be 49983")
offline = data.get("offline_bundle", {})
if "envd-docker" not in offline.get("artifact_name_template", ""):
    raise SystemExit("offline bundle name must include envd-docker")
PY

echo "sandbox android envd catalog contract tests OK"
