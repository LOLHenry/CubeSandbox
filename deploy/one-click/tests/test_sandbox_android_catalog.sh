#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="${SCRIPT_DIR}/../assets/sandbox-catalog/sandbox-android-kunpeng-arm64.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${CATALOG}" ]] || fail "missing catalog file: ${CATALOG}"

python3 - "${CATALOG}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

required = [
    "id", "instance_type", "platform", "workload", "template_defaults",
]
for key in required:
    if key not in data:
        raise SystemExit(f"missing key: {key}")

if data["id"] != "sandbox-android-kunpeng-arm64":
    raise SystemExit(f"unexpected id: {data['id']}")
if data["instance_type"] != "android":
    raise SystemExit(f"unexpected instance_type: {data['instance_type']}")
if data["platform"].get("arch") != "arm64":
    raise SystemExit("platform.arch must be arm64")
if data["workload"].get("android_version") != "16":
    raise SystemExit("workload.android_version must be 16")
if "16.0.0_64only" not in data["workload"].get("upstream_image", ""):
    raise SystemExit("upstream_image must reference ReDroid 16.0.0_64only")
published = data["workload"].get("published_images", {})
for reg in ("cn", "intl"):
    if reg not in published:
        raise SystemExit(f"missing published_images.{reg}")
    if "sandbox-android-redroid:16.0.0-arm64" not in published[reg]:
        raise SystemExit(f"unexpected published image for {reg}")
if 5555 not in data["template_defaults"].get("expose_ports", []):
    raise SystemExit("template_defaults.expose_ports must include 5555")
PY

echo "sandbox android catalog contract tests OK"
