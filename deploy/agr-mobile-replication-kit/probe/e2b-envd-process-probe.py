#!/usr/bin/env python3
"""Probe whether an envd *process* exists on AGR mobile via E2B SDK surfaces.

Checks control-plane metadata (envd_version), data-plane envd HTTP (:49983),
and envd-backed SDK APIs (commands / files / pty / is_running).
"""
from __future__ import annotations

import json
import os
import sys
import traceback
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any

import httpx

os.environ.setdefault("E2B_DOMAIN", "ap-shanghai.tencentags.com")
os.environ.setdefault("E2B_VALIDATE_API_KEY", "false")

if not os.environ.get("E2B_API_KEY"):
    print("ERROR: set E2B_API_KEY (AGR API Key)", file=sys.stderr)
    sys.exit(2)


@dataclass
class ProbeResult:
    probe: str = "e2b-sdk-envd-process"
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    domain: str = os.environ["E2B_DOMAIN"]
    template: str = ""
    sandbox_id: str = ""
    tests: list[dict[str, Any]] = field(default_factory=list)
    conclusion: dict[str, Any] = field(default_factory=dict)


def record(result: ProbeResult, name: str, ok: bool | None, detail: dict[str, Any]) -> None:
    result.tests.append({"name": name, "ok": ok, "detail": detail})
    status = {True: "OK", False: "FAIL", None: "SKIP"}.get(ok, str(ok))
    print(f"\n=== {name} [{status}] ===")
    print(json.dumps(detail, indent=2, ensure_ascii=False, default=str))


def safe_call(name: str, fn, result: ProbeResult) -> Any:
    try:
        value = fn()
        record(result, name, True, {"value": value})
        return value
    except Exception as e:
        record(
            result,
            name,
            False,
            {"error": repr(e), "traceback": traceback.format_exc()},
        )
        return None


def probe_envd_http(host: str, token: str | None, path: str = "/health") -> dict[str, Any]:
    url = f"https://{host}{path}"
    headers: dict[str, str] = {}
    if token:
        headers["X-Access-Token"] = token
    with httpx.Client(timeout=15.0, verify=True) as client:
        r = client.get(url, headers=headers)
        body = r.text[:500]
        return {
            "url": url,
            "status_code": r.status_code,
            "headers": dict(r.headers),
            "body_preview": body,
        }


def _probe_pty(sandbox) -> dict[str, Any]:
    from e2b.sandbox.commands.command_handle import PtySize

    handle = sandbox.pty.create(PtySize(rows=24, cols=80), timeout=10)
    return {"pid": handle.pid}


def main() -> int:
    from e2b import Sandbox

    result = ProbeResult()
    template = os.environ.get("E2B_TEMPLATE", "mobile-arch-probe-1787551777")
    result.template = template
    sandbox = None

    try:
        sandbox = Sandbox.create(template=template, timeout=600)
        result.sandbox_id = sandbox.sandbox_id

        create_detail = {
            "sandbox_id": sandbox.sandbox_id,
            "template": template,
            "envd_version_attr": str(getattr(sandbox, "_envd_version", None)),
            "envd_access_token_present": bool(
                getattr(sandbox, "_envd_access_token", None)
            ),
            "envd_api_url": getattr(sandbox, "envd_api_url", None),
            "envd_direct_url": getattr(sandbox, "envd_direct_url", None),
            "host_49983": sandbox.get_host(49983),
            "host_4723": sandbox.get_host(4723),
        }
        record(result, "sandbox.create", True, create_detail)
    except Exception as e:
        record(
            result,
            "sandbox.create",
            False,
            {"error": repr(e), "traceback": traceback.format_exc()},
        )
        _write_result(result)
        return 1

    token = getattr(sandbox, "_envd_access_token", None)
    host_49983 = sandbox.get_host(49983)
    host_4723 = sandbox.get_host(4723)

    safe_call(
        "sandbox.get_info.envd_version",
        lambda: {
            "envd_version": sandbox.get_info().envd_version,
            "state": str(sandbox.get_info().state),
            "cpu_count": sandbox.get_info().cpu_count,
            "memory_mb": sandbox.get_info().memory_mb,
        },
        result,
    )

    safe_call(
        "sandbox.is_running",
        lambda: sandbox.is_running(),
        result,
    )

    safe_call(
        "https.get_host_49983.health",
        lambda: probe_envd_http(host_49983, token, "/health"),
        result,
    )

    safe_call(
        "https.get_host_49983.root",
        lambda: probe_envd_http(host_49983, token, "/"),
        result,
    )

    if getattr(sandbox, "envd_api_url", None):
        safe_call(
            "https.envd_api_url.health",
            lambda: probe_envd_http(
                sandbox.envd_api_url.replace("https://", "").replace("http://", "").rstrip("/"),
                token,
                "/health",
            )
            if sandbox.envd_api_url.startswith("http")
            else {"note": "envd_api_url is not absolute", "value": sandbox.envd_api_url},
            result,
        )

    safe_call(
        "commands.run.ps_envd",
        lambda: {
            "stdout": sandbox.commands.run(
                "ps -A 2>/dev/null | grep -i envd || pgrep -a envd || echo NO_ENVD_PROCESS",
                timeout=30,
            ).stdout,
            "stderr": sandbox.commands.run(
                "ps -A 2>/dev/null | grep -i envd || pgrep -a envd || echo NO_ENVD_PROCESS",
                timeout=30,
            ).stderr,
            "exit_code": sandbox.commands.run(
                "ps -A 2>/dev/null | grep -i envd || pgrep -a envd || echo NO_ENVD_PROCESS",
                timeout=30,
            ).exit_code,
        },
        result,
    )

    safe_call(
        "commands.run.pid1",
        lambda: {
            "stdout": sandbox.commands.run(
                "tr '\\0' ' ' </proc/1/cmdline; echo",
                timeout=30,
            ).stdout,
            "exit_code": sandbox.commands.run(
                "tr '\\0' ' ' </proc/1/cmdline; echo",
                timeout=30,
            ).exit_code,
        },
        result,
    )

    safe_call(
        "files.read.proc_1_cmdline",
        lambda: sandbox.files.read("/proc/1/cmdline"),
        result,
    )

    safe_call(
        "pty.create",
        lambda: _probe_pty(sandbox),
        result,
    )

    safe_call(
        "https.get_host_4723.status",
        lambda: probe_envd_http(host_4723, token, "/status"),
        result,
    )

    # Synthesize conclusion from test outcomes.
    by_name = {t["name"]: t for t in result.tests}
    control_envd_version = (
        by_name.get("sandbox.get_info.envd_version", {})
        .get("detail", {})
        .get("value", {})
        .get("envd_version")
    )
    commands_ok = by_name.get("commands.run.ps_envd", {}).get("ok") is True
    health_ok = by_name.get("sandbox.is_running", {}).get("ok") is True
    https_health = by_name.get("https.get_host_49983.health", {}).get("detail", {}).get(
        "value", {}
    )
    https_status = https_health.get("status_code") if isinstance(https_health, dict) else None

    result.conclusion = {
        "control_plane_reports_envd_version": bool(control_envd_version),
        "envd_version": control_envd_version,
        "envd_data_plane_reachable": health_ok or https_status in (200, 204),
        "envd_process_observable_via_commands": commands_ok,
        "interpretation": (
            "If control_plane_reports_envd_version is True but "
            "envd_data_plane_reachable and envd_process_observable_via_commands are False, "
            "the platform advertises envd metadata/token but mobile does not expose a "
            "working envd endpoint or process shell access."
        ),
    }
    record(result, "conclusion", None, result.conclusion)

    try:
        sandbox.kill()
        record(result, "sandbox.kill", True, {"sandbox_id": sandbox.sandbox_id})
    except Exception as e:
        record(result, "sandbox.kill", False, {"error": repr(e)})

    _write_result(result)
    return 0


def _write_result(result: ProbeResult) -> None:
    out = os.environ.get(
        "PROBE_OUT",
        "deploy/agr-mobile-replication-kit/probe/artifacts/04-20260824-e2b-envd-process/result.json",
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    payload = asdict(result)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False, default=str)
    print(f"\nWrote {out}")


if __name__ == "__main__":
    sys.exit(main())
