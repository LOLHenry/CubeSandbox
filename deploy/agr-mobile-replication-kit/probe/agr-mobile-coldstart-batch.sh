#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNS="${1:-5}"
GAP_SEC="${AGR_BATCH_GAP_SEC:-30}"
TOOL_ID="${AGR_TOOL_ID:-}"

cd "${ROOT}"

echo "==> Batch cold-start: runs=${RUNS} gap=${GAP_SEC}s tool=${TOOL_ID:-<new each run>}"
for i in $(seq 1 "${RUNS}"); do
  echo ""
  echo "========== Run ${i}/${RUNS} $(date -u +%Y-%m-%dT%H:%M:%SZ) =========="
  if [[ -n "${TOOL_ID}" ]]; then
  AGR_TOOL_ID="${TOOL_ID}" python3 "${SCRIPT_DIR}/agr-mobile-coldstart-bench.py" || true
  else
    python3 "${SCRIPT_DIR}/agr-mobile-coldstart-bench.py" || true
  fi
  if [[ "${i}" -lt "${RUNS}" ]]; then
    echo "Sleeping ${GAP_SEC}s before next run..."
    sleep "${GAP_SEC}"
  fi
done

python3 - "${RUNS}" "${SCRIPT_DIR}" <<'PY'
import json
import statistics
import sys
from pathlib import Path

runs = int(sys.argv[1])
script_dir = Path(sys.argv[2])
artifact_root = script_dir / "artifacts"
dirs = sorted(artifact_root.glob("coldstart-*"), key=lambda p: p.stat().st_mtime, reverse=True)[:runs]
dirs = sorted(dirs, key=lambda p: p.name)

metrics = [
    "t_api_create", "t_status_running", "t_token",
    "t_health_ready", "t_appium_ready", "t_scrcpy_ready",
    "t_adb_ready", "t_android_boot", "t_e2e_usable",
]
gap_metrics = [
    "api_to_running", "running_to_token", "token_to_e2e",
    "running_to_e2e", "total_create_to_e2e",
]

rows = []
for d in dirs:
    f = d / "result.json"
    if not f.exists():
        continue
    data = json.loads(f.read_text())
    rows.append({
        "run_id": data.get("run_id"),
        "success": data.get("success"),
        "instance_id": data.get("instance_id"),
        "timestamps_ms": data.get("timestamps_ms", {}),
        "gaps_ms": data.get("gaps_ms", {}),
        "failure_stage": data.get("failure_stage"),
    })


def pct(vals, p):
    if not vals:
        return None
    vals = sorted(vals)
    k = (len(vals) - 1) * p / 100
    f = int(k)
    c = min(f + 1, len(vals) - 1)
    if f == c:
        return round(vals[f], 1)
    return round(vals[f] + (vals[c] - vals[f]) * (k - f), 1)


summary = {
    "batch_runs_requested": runs,
    "batch_runs_collected": len(rows),
    "success_count": sum(1 for r in rows if r.get("success")),
    "success_rate": round(sum(1 for r in rows if r.get("success")) / len(rows), 3) if rows else 0,
    "runs": rows,
    "percentiles_ms": {},
    "gap_percentiles_ms": {},
}

for m in metrics:
    vals = [r["timestamps_ms"].get(m) for r in rows if r["timestamps_ms"].get(m) is not None]
    if vals:
        summary["percentiles_ms"][m] = {
            "n": len(vals),
            "min": round(min(vals), 1),
            "p50": pct(vals, 50),
            "p90": pct(vals, 90),
            "max": round(max(vals), 1),
            "mean": round(statistics.mean(vals), 1),
        }

for m in gap_metrics:
    vals = [r["gaps_ms"].get(m) for r in rows if r["gaps_ms"].get(m) is not None]
    if vals:
        summary["gap_percentiles_ms"][m] = {
            "n": len(vals),
            "min": round(min(vals), 1),
            "p50": pct(vals, 50),
            "p90": pct(vals, 90),
            "max": round(max(vals), 1),
            "mean": round(statistics.mean(vals), 1),
        }

out = artifact_root / f"coldstart-batch-summary-{runs}runs.json"
out.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(summary, indent=2, ensure_ascii=False))
print(f"\nWrote {out}")
PY
