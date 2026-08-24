#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Probe Tencent AGR mobile sandbox (requires TENCENTCLOUD_SECRET_ID/KEY).
# Based on 2026-07-23 experiment: https://github.com/LOLHenry/android-cuttlefish/...
set -euo pipefail

AGR_BIN="${AGR_BIN:-agr}"
REGION="${AGR_REGION:-ap-shanghai}"
DOMAIN="${AGR_DOMAIN:-tencentags.com}"
TOOL_NAME="${AGR_MOBILE_TOOL_NAME:-mobile-probe-$(date +%s)}"
TIMEOUT="${AGR_INSTANCE_TIMEOUT:-30m}"

if [[ -z "${TENCENTCLOUD_SECRET_ID:-}" || -z "${TENCENTCLOUD_SECRET_KEY:-}" ]]; then
  echo "Set TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY" >&2
  exit 4
fi

command -v "$AGR_BIN" >/dev/null || { echo "agr CLI not found" >&2; exit 2; }

"$AGR_BIN" init --secret-id "$TENCENTCLOUD_SECRET_ID" --secret-key "$TENCENTCLOUD_SECRET_KEY" --non-interactive -o json
"$AGR_BIN" config set region "$REGION"
"$AGR_BIN" config set domain "$DOMAIN"

echo "==> agr version"
"$AGR_BIN" version -o json

echo "==> create mobile tool: $TOOL_NAME"
TOOL_ID="$("$AGR_BIN" tool create \
  --tool-name "$TOOL_NAME" \
  --tool-type mobile \
  --network-configuration '{"NetworkMode":"PUBLIC"}' \
  --default-timeout "$TIMEOUT" \
  -o json --non-interactive --jq '.Data.ToolId')"

echo "ToolId=$TOOL_ID"
sleep 5
"$AGR_BIN" tool get "$TOOL_ID" -o json

echo "==> create instance"
INSTANCE_ID="$("$AGR_BIN" instance create --tool-id "$TOOL_ID" --timeout "$TIMEOUT" \
  -o json --non-interactive --jq '.Data.InstanceId')"
echo "InstanceId=$INSTANCE_ID"

"$AGR_BIN" instance get "$INSTANCE_ID" -o json

echo "==> mobile connect"
"$AGR_BIN" instance mobile connect "$INSTANCE_ID" -o json

echo "==> fingerprint (compare with CubeSandbox replica)"
"$AGR_BIN" instance mobile adb "$INSTANCE_ID" -- shell \
  'getprop ro.build.display.id; getprop ro.hardware.gralloc; cat /sys/class/dmi/id/product_name; getprop ro.build.version.release'

echo "==> listening ports"
"$AGR_BIN" instance mobile adb "$INSTANCE_ID" -- shell 'ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || true' | head -40

echo "DONE InstanceId=$INSTANCE_ID ToolId=$TOOL_ID"
echo "Cleanup: agr instance delete $INSTANCE_ID; agr tool delete $TOOL_ID"
