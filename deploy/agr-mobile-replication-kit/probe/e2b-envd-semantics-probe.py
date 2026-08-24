#!/usr/bin/env python3
"""Probe E2B SDK envd semantics on AGR mobile sandbox."""
import json
import os
import sys
import traceback
from datetime import datetime, timezone

os.environ.setdefault("E2B_DOMAIN", "ap-shanghai.tencentags.com")
os.environ.setdefault("E2B_VALIDATE_API_KEY", "false")

if not os.environ.get("E2B_API_KEY"):
    print("ERROR: set E2B_API_KEY (AGR API Key)", file=sys.stderr)
    sys.exit(2)

RESULT = {
    "probe": "e2b-sdk-envd-semantics",
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "domain": os.environ["E2B_DOMAIN"],
    "tests": [],
}


def record(name, ok, detail):
    RESULT["tests"].append({"name": name, "ok": ok, "detail": detail})
    print(f"\n=== {name} ===")
    print(json.dumps(detail, indent=2, ensure_ascii=False, default=str))


def main():
    from e2b import Sandbox

    template = os.environ.get("E2B_TEMPLATE", "mobile-arch-probe-1787551777")
    sandbox = None

    try:
        sandbox = Sandbox.create(template=template, timeout=600)
        record(
            "sandbox.create",
            True,
            {
                "sandbox_id": sandbox.sandbox_id,
                "template": template,
                "envd_access_token_present": bool(
                    getattr(sandbox, "_envd_access_token", None)
                ),
                "host_49983": sandbox.get_host(49983),
                "host_4723": sandbox.get_host(4723),
            },
        )
    except Exception as e:
        record(
            "sandbox.create",
            False,
            {"error": repr(e), "traceback": traceback.format_exc()},
        )
        print(json.dumps(RESULT, indent=2, ensure_ascii=False, default=str))
        return 1

    try:
        result = sandbox.commands.run("echo hi", timeout=30)
        record(
            "commands.run",
            True,
            {
                "stdout": result.stdout,
                "stderr": result.stderr,
                "exit_code": result.exit_code,
            },
        )
    except Exception as e:
        record(
            "commands.run",
            False,
            {"error": repr(e), "traceback": traceback.format_exc()},
        )

    try:
        path = "/tmp/e2b-probe.txt"
        content = "hello-from-e2b-sdk"
        sandbox.files.write(path, content)
        read_back = sandbox.files.read(path)
        record(
            "files.write_read",
            True,
            {"path": path, "written": content, "read_back": read_back},
        )
    except Exception as e:
        record(
            "files.write_read",
            False,
            {"error": repr(e), "traceback": traceback.format_exc()},
        )

    try:
        health = sandbox.is_running()
        record("sandbox.is_running", True, {"is_running": health})
    except Exception as e:
        record("sandbox.is_running", False, {"error": repr(e)})

    try:
        sandbox.kill()
        record("sandbox.kill", True, {"sandbox_id": sandbox.sandbox_id})
    except Exception as e:
        record("sandbox.kill", False, {"error": repr(e)})

    out = os.environ.get("PROBE_OUT", "e2b-envd-probe-result.json")
    with open(out, "w") as f:
        json.dump(RESULT, f, indent=2, ensure_ascii=False, default=str)
    print(f"\nWrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
