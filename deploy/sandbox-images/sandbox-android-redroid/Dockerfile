# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Official CubeSandbox Android workload image for Kunpeng ARM64.
# Wraps upstream ReDroid AOSP 16 (64-bit only) with CubeSandbox metadata labels.
#
# Build (on aarch64 host or buildx):
#   docker build --platform linux/arm64 \
#     -t cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64 .
#
# Publish:
#   docker push cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid:16.0.0-arm64

FROM redroid/redroid:16.0.0_64only-latest

LABEL org.opencontainers.image.title="CubeSandbox Android Sandbox (ReDroid AOSP 16)"
LABEL org.opencontainers.image.description="ReDroid Android 16 workload for CubeVM + cube-agent on Kunpeng ARM64"
LABEL org.opencontainers.image.vendor="Tencent Cloud CubeSandbox"
LABEL org.cubesandbox.sandbox.id="sandbox-android-kunpeng-arm64"
LABEL org.cubesandbox.sandbox.category="android"
LABEL org.cubesandbox.sandbox.platform="kunpeng-arm64"
LABEL org.cubesandbox.android.version="16"
LABEL org.cubesandbox.android.engine="redroid"
LABEL org.cubesandbox.instance_type="android"
LABEL org.cubesandbox.runtime_model="cubevm-redroid"

# Default ReDroid boot properties (overridable at container create).
ENV CUBESANDBOX_REDROID_WIDTH=1080
ENV CUBESANDBOX_REDROID_HEIGHT=1920
ENV CUBESANDBOX_REDROID_DPI=480
ENV CUBESANDBOX_REDROID_GPU_MODE=guest
