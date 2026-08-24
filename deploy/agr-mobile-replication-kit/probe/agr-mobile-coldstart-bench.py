#!/usr/bin/env python3
"""AGR mobile sandbox cold-start benchmark (single run).

Measures control-plane and data-plane readiness milestones discussed in
docs/probes design: t_api_create, t_status_running, t_token, t_*_ready, t_e2e_usable.

Usage:
  export TENCENTCLOUD_SECRET_ID=... TENCENTCLOUD_SECRET_KEY=...
  export AGR_REGION=ap-shanghai AGR_DOMAIN=tencentags.com
  python3 probe/agr-mobile-coldstart-bench.py

Optional:
  AGR_TOOL_ID=sdt-xxx     reuse existing mobile tool (skip tool create)
  AGR_KEEP_INSTANCE=1       do not delete instance after run
  AGR_KEEP_TOOL=1         do not delete tool when script created it
  AGR_RUNNING_TIMEOUT=600 max seconds waiting for RUNNING
  AGR_PROBE_TIMEOUT=300   max seconds for data-plane probes after token
  ADB_PATH=/path/to/adb
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

SCRIPT_DIR = Path(__file__).resolve().parent
ARTIFACT_ROOT = SCRIPT_DIR / "artifacts"
AGR_BIN = os.environ.get("AGR_BIN", "agr")
REGION = os.environ.get("AGR_REGION", "ap-shanghai")
DOMAIN = os.environ.get("AGR_DOMAIN", "tencentags.com")
RUNNING_TIMEOUT = int(os.environ.get("AGR_RUNNING_TIMEOUT", "600"))
PROBE_TIMEOUT = int(os.environ.get("AGR_PROBE_TIMEOUT", "300"))
INSTANCE_TIMEOUT = os.environ.get("AGR_INSTANCE_TIMEOUT", "30m")
ADB_PATH = os.environ.get("ADB_PATH") or shutil.which("adb") or "/tmp/platform-tools/adb"

TERMINAL_STATUSES = {
    "STARTING_FAILED",
    "FAILED",
    "STOPPED",
    "STOPPING",
    "STOPPING_FAILED",
}


@dataclass
class BenchResult:
    run_id: str = field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    )
    timestamp_utc: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    environment: dict[str, Any] = field(default_factory=dict)
    tool_id: str = ""
    tool_created: bool = False
    instance_id: str = ""
    success: bool = False
    failure_stage: str | None = None
    final_status: str | None = None
    timestamps_ms: dict[str, float | None] = field(default_factory=dict)
    status_poll_log: list[dict[str, Any]] = field(default_factory=list)
    probe_details: dict[str, Any] = field(default_factory=dict)
    gaps_ms: dict[str, float | None] = field(default_factory=dict)


def ms_since(t0: float) -> float:
    return round((time.monotonic() - t0) * 1000, 1)


def run_agr(args: list[str], *, jq: str | None = None) -> dict[str, Any] | str:
    cmd = [AGR_BIN, *args, "-o", "json", "--non-interactive"]
    if jq:
        cmd.extend(["--jq", jq])
    env = os.environ.copy()
    env.setdefault("ADB_PATH", ADB_PATH)
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )
    if proc.returncode != 0:
        msg = proc.stderr.strip() or proc.stdout.strip()
        raise RuntimeError(
            f"agr {' '.join(args)} failed (exit {proc.returncode}): {msg}"
        )
    raw = proc.stdout.strip()
    if not raw:
        return {}
    if jq:
        return raw
    return json.loads(raw)


def agr_init() -> None:
    if not os.environ.get("TENCENTCLOUD_SECRET_ID") or not os.environ.get(
        "TENCENTCLOUD_SECRET_KEY"
    ):
        raise SystemExit("Set TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY")
    try:
        run_agr(
            [
                "init",
                "--secret-id",
                os.environ["TENCENTCLOUD_SECRET_ID"],
                "--secret-key",
                os.environ["TENCENTCLOUD_SECRET_KEY"],
            ]
        )
    except RuntimeError as e:
        if "CONFIG_EXISTS" not in str(e):
            raise
    run_agr(["config", "set", "region", REGION])
    run_agr(["config", "set", "domain", DOMAIN])
    doctor = run_agr(["doctor"])
    checks = (doctor.get("Data") or {}).get("Checks") or []
    failed = [c for c in checks if c.get("Status") != "ok"]
    if failed:
        raise RuntimeError(f"agr doctor failed: {failed}")


def ensure_tool(result: BenchResult) -> str:
    existing = os.environ.get("AGR_TOOL_ID", "").strip()
    if existing:
        result.tool_id = existing
        result.tool_created = False
        return existing
    tool_name = os.environ.get(
        "AGR_TOOL_NAME", f"mobile-coldstart-{int(time.time())}"
    )
    payload = run_agr(
        [
            "tool",
            "create",
            "--tool-name",
            tool_name,
            "--tool-type",
            "mobile",
            "--network-configuration",
            '{"NetworkMode":"PUBLIC"}',
            "--default-timeout",
            INSTANCE_TIMEOUT,
        ],
        jq=".Data.ToolId",
    )
    tool_id = str(payload).strip()
    result.tool_id = tool_id
    result.tool_created = True
    return tool_id


def poll_until_running(
    result: BenchResult, instance_id: str, t0: float
) -> str:
    interval = 1.0
    deadline = time.monotonic() + RUNNING_TIMEOUT
    last_status = None
    while time.monotonic() < deadline:
        loop_start = time.monotonic()
        resp = run_agr(["instance", "get", instance_id])
        data = resp.get("Data") or {}
        status = data.get("Status", "UNKNOWN")
        duration_ms = (resp.get("Meta") or {}).get("DurationMs")
        elapsed = ms_since(t0)
        result.status_poll_log.append(
            {
                "elapsed_ms": elapsed,
                "status": status,
                "api_duration_ms": duration_ms,
            }
        )
        last_status = status
        if status == "RUNNING":
            result.timestamps_ms["t_status_running"] = elapsed
            result.final_status = status
            return status
        if status in TERMINAL_STATUSES:
            result.final_status = status
            result.failure_stage = f"status_{status}"
            raise RuntimeError(f"instance entered terminal status {status}")
        sleep_for = interval
        if elapsed > 120_000:
            interval = 2.0
            sleep_for = interval
        if duration_ms:
            sleep_for = max(0.0, sleep_for - float(duration_ms) / 1000.0)
        time.sleep(sleep_for)
    result.failure_stage = "status_running_timeout"
    raise TimeoutError(
        f"Status did not become RUNNING within {RUNNING_TIMEOUT}s (last={last_status})"
    )


def acquire_token(instance_id: str, t0: float, result: BenchResult) -> str:
    resp = run_agr(
        [
            "api",
            "call",
            "AcquireSandboxInstanceToken",
            "--request",
            json.dumps({"InstanceId": instance_id}),
        ]
    )
    assert isinstance(resp, dict)
    data = resp.get("Data") or {}
    inner = data.get("Response") or data
    if isinstance(inner, dict) and "Response" in inner:
        inner = inner["Response"]
    token = None
    if isinstance(inner, dict):
        token = inner.get("Token")
    if not token:
        raise RuntimeError("AcquireSandboxInstanceToken returned no Token")
    result.timestamps_ms["t_token"] = ms_since(t0)
    if isinstance(inner, dict):
        result.probe_details["token_expires_at"] = inner.get("ExpiresAt")
    return str(token)


def host_for(instance_id: str, port: int) -> str:
    return f"{port}-{instance_id}.{REGION}.{DOMAIN}"


def probe_https(
    name: str,
    url: str,
    token: str,
    *,
    ok_status: set[int] | None = None,
    body_contains: str | None = None,
) -> tuple[bool, dict[str, Any]]:
    ok_status = ok_status or {200, 204}
    headers = {"X-Access-Token": token}
    detail: dict[str, Any] = {"url": url}
    try:
        with httpx.Client(timeout=15.0, verify=True) as client:
            r = client.get(url, headers=headers)
        detail["status_code"] = r.status_code
        detail["body_preview"] = r.text[:300]
        if r.status_code not in ok_status:
            return False, detail
        if body_contains and body_contains not in r.text:
            return False, detail
        return True, detail
    except Exception as e:
        detail["error"] = repr(e)
        return False, detail


def probe_appium(host: str, token: str) -> tuple[bool, dict[str, Any]]:
    return probe_https(
        "appium",
        f"https://{host}/status",
        token,
        ok_status={200},
        body_contains='"ready":true',
    )


def probe_health(host: str, token: str) -> tuple[bool, dict[str, Any]]:
    for path in ("/healthz", "/livez"):
        ok, detail = probe_https(
            "health",
            f"https://{host}{path}",
            token,
            ok_status={200},
        )
        detail["path"] = path
        if ok:
            return True, detail
    return False, detail


def probe_scrcpy(host: str, token: str) -> tuple[bool, dict[str, Any]]:
    return probe_https(
        "scrcpy",
        f"https://{host}/",
        token,
        ok_status={200},
    )


def probe_adb(instance_id: str, t0: float) -> tuple[bool, dict[str, Any]]:
    detail: dict[str, Any] = {"adb_path": ADB_PATH}
    env = os.environ.copy()
    env["ADB_PATH"] = ADB_PATH
    env["PATH"] = f"{Path(ADB_PATH).parent}:{env.get('PATH', '')}"
    try:
        subprocess.run(
            [AGR_BIN, "instance", "mobile", "connect", instance_id, "-o", "json", "--non-interactive"],
            capture_output=True,
            text=True,
            env=env,
            timeout=120,
            check=True,
        )
        detail["connect"] = "ok"
        proc = subprocess.run(
            [ADB_PATH, "devices"],
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )
        detail["adb_devices_stdout"] = proc.stdout.strip()
        if proc.returncode != 0:
            detail["adb_devices_stderr"] = proc.stderr.strip()
            return False, detail
        lines = [ln for ln in proc.stdout.splitlines() if "\tdevice" in ln]
        detail["device_lines"] = lines
        if not lines:
            return False, detail
        serial = lines[0].split("\t")[0]
        detail["serial"] = serial
        boot = subprocess.run(
            [ADB_PATH, "-s", serial, "shell", "getprop", "sys.boot_completed"],
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )
        detail["boot_completed_stdout"] = boot.stdout.strip()
        if boot.stdout.strip() == "1":
            result_boot = True
        else:
            result_boot = False
        return True, detail
    except Exception as e:
        detail["error"] = repr(e)
        return False, detail


def poll_data_plane(
    result: BenchResult,
    instance_id: str,
    token: str,
    t0: float,
) -> None:
    hosts = {
        "appium": host_for(instance_id, 4723),
        "health": host_for(instance_id, 8080),
        "scrcpy": host_for(instance_id, 8000),
    }
    probes = {
        "t_appium_ready": lambda: probe_appium(hosts["appium"], token),
        "t_health_ready": lambda: probe_health(hosts["health"], token),
        "t_scrcpy_ready": lambda: probe_scrcpy(hosts["scrcpy"], token),
    }
    adb_done = False
    android_boot_done = False
    deadline = time.monotonic() + PROBE_TIMEOUT
    result.probe_details["hosts"] = hosts

    while time.monotonic() < deadline:
        pending = [k for k, v in result.timestamps_ms.items() if k.startswith("t_") and v is None]
        # only poll incomplete service probes
        with ThreadPoolExecutor(max_workers=3) as pool:
            futures = {}
            for key, fn in probes.items():
                if result.timestamps_ms.get(key) is None:
                    futures[pool.submit(fn)] = key
            for fut in as_completed(futures):
                key = futures[fut]
                ok, detail = fut.result()
                result.probe_details[key] = detail
                if ok:
                    result.timestamps_ms[key] = ms_since(t0)

        if result.timestamps_ms.get("t_adb_ready") is None and not adb_done:
            ok, detail = probe_adb(instance_id, t0)
            result.probe_details["t_adb_ready"] = detail
            if ok:
                result.timestamps_ms["t_adb_ready"] = ms_since(t0)
                adb_done = True
                if detail.get("boot_completed_stdout") == "1":
                    result.timestamps_ms["t_android_boot"] = result.timestamps_ms["t_adb_ready"]
                    android_boot_done = True
            else:
                # retry adb less aggressively
                time.sleep(3)

        if adb_done and not android_boot_done:
            serial = (result.probe_details.get("t_adb_ready") or {}).get("serial")
            if serial:
                try:
                    boot = subprocess.run(
                        [ADB_PATH, "-s", serial, "shell", "getprop", "sys.boot_completed"],
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    if boot.stdout.strip() == "1":
                        result.timestamps_ms["t_android_boot"] = ms_since(t0)
                        android_boot_done = True
                except Exception:
                    pass

        required = ["t_appium_ready", "t_adb_ready"]
        if all(result.timestamps_ms.get(k) is not None for k in required):
            break
        time.sleep(2)

    if result.timestamps_ms.get("t_e2e_usable") is None:
        a = result.timestamps_ms.get("t_appium_ready")
        b = result.timestamps_ms.get("t_adb_ready")
        if a is not None and b is not None:
            result.timestamps_ms["t_e2e_usable"] = max(a, b)


def compute_gaps(result: BenchResult) -> None:
    ts = result.timestamps_ms
    result.gaps_ms = {
        "api_to_running": _gap(ts.get("t_api_create"), ts.get("t_status_running")),
        "running_to_token": _gap(ts.get("t_status_running"), ts.get("t_token")),
        "token_to_e2e": _gap(ts.get("t_token"), ts.get("t_e2e_usable")),
        "running_to_e2e": _gap(ts.get("t_status_running"), ts.get("t_e2e_usable")),
        "total_create_to_e2e": _gap(ts.get("t_api_create"), ts.get("t_e2e_usable")),
    }


def _gap(a: float | None, b: float | None) -> float | None:
    if a is None or b is None:
        return None
    return round(b - a, 1)


def cleanup(result: BenchResult) -> None:
    if result.instance_id and not os.environ.get("AGR_KEEP_INSTANCE"):
        try:
            run_agr(
                ["instance", "delete", result.instance_id, "--ignore-not-found"]
            )
        except Exception as e:
            result.probe_details["cleanup_instance_error"] = repr(e)
    if result.tool_created and result.tool_id and not os.environ.get("AGR_KEEP_TOOL"):
        try:
            run_agr(["tool", "delete", result.tool_id, "--ignore-not-found"])
        except Exception as e:
            result.probe_details["cleanup_tool_error"] = repr(e)


def main() -> int:
    t0 = time.monotonic()
    result = BenchResult()
    result.environment = {
        "region": REGION,
        "domain": DOMAIN,
        "agr_bin": AGR_BIN,
        "agr_version": subprocess.check_output([AGR_BIN, "version"], text=True).strip(),
        "adb_path": ADB_PATH,
        "running_timeout_s": RUNNING_TIMEOUT,
        "probe_timeout_s": PROBE_TIMEOUT,
        "hostname": os.environ.get("HOSTNAME", ""),
    }
    result.timestamps_ms = {
        "t_api_create": None,
        "t_status_running": None,
        "t_token": None,
        "t_health_ready": None,
        "t_appium_ready": None,
        "t_scrcpy_ready": None,
        "t_adb_ready": None,
        "t_android_boot": None,
        "t_e2e_usable": None,
    }

    out_dir = ARTIFACT_ROOT / f"coldstart-{result.run_id}"
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        agr_init()
        tool_id = ensure_tool(result)
        print(f"ToolId={tool_id} (created={result.tool_created})")

        create_resp = run_agr(
            [
                "instance",
                "create",
                "--tool-id",
                tool_id,
                "--timeout",
                INSTANCE_TIMEOUT,
            ]
        )
        result.timestamps_ms["t_api_create"] = ms_since(t0)
        data = create_resp.get("Data") or {}
        instance_id = data.get("InstanceId")
        if not instance_id:
            raise RuntimeError(f"create returned no InstanceId: {create_resp}")
        result.instance_id = instance_id
        result.final_status = data.get("Status")
        print(f"InstanceId={instance_id} initial_status={result.final_status}")

        if result.final_status != "RUNNING":
            poll_until_running(result, instance_id, t0)
        else:
            result.timestamps_ms["t_status_running"] = result.timestamps_ms[
                "t_api_create"
            ]

        token = acquire_token(instance_id, t0, result)
        result.probe_details["token_prefix"] = token[:12] + "..."

        poll_data_plane(result, instance_id, token, t0)
        compute_gaps(result)

        result.success = result.timestamps_ms.get("t_e2e_usable") is not None
        if not result.success:
            result.failure_stage = result.failure_stage or "data_plane_timeout"

    except Exception as e:
        result.failure_stage = result.failure_stage or type(e).__name__
        result.probe_details["fatal_error"] = str(e)
        print(f"ERROR: {e}", file=sys.stderr)
    finally:
        cleanup(result)

    result_path = out_dir / "result.json"
    result_path.write_text(
        json.dumps(asdict(result), indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print("\n=== Cold-start benchmark result ===")
    print(json.dumps(asdict(result), indent=2, ensure_ascii=False))
    print(f"\nWrote {result_path}")
    return 0 if result.success else 1


if __name__ == "__main__":
    sys.exit(main())
