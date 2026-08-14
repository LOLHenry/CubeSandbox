# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# CubeSandbox Android workload image with envd for cubebox template flow.
# Wraps sandbox-android-redroid (ReDroid AOSP 16) and injects envd from cubesandbox-base.
#
# Build (on aarch64 host or buildx):
#   docker build --platform linux/arm64 \
#     -t cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-envd:16.0.0-arm64 .

ARG REDROID_BASE_IMAGE=sandbox-android-redroid:16.0.0-arm64
# ghcr cubesandbox-base may lack arm64 on some registries; build.sh falls back to sandbox-code.
ARG ENVD_BASE_IMAGE=ghcr.io/tencentcloud/cubesandbox-base:2026.16

FROM ${ENVD_BASE_IMAGE} AS envd-source

FROM ${REDROID_BASE_IMAGE}

COPY --from=envd-source --chmod=755 /usr/bin/envd /usr/bin/envd

COPY --chmod=755 android-redroid-entrypoint.sh /usr/local/bin/android-redroid-entrypoint.sh

LABEL org.opencontainers.image.title="CubeSandbox Android Sandbox (ReDroid AOSP 16 + envd)"
LABEL org.opencontainers.image.description="ReDroid Android 16 with envd for cubebox templates on Kunpeng ARM64"
LABEL org.opencontainers.image.vendor="Tencent Cloud CubeSandbox"
LABEL org.cubesandbox.sandbox.id="sandbox-android-kunpeng-arm64-envd"
LABEL org.cubesandbox.sandbox.category="android"
LABEL org.cubesandbox.sandbox.platform="kunpeng-arm64"
LABEL org.cubesandbox.android.version="16"
LABEL org.cubesandbox.android.engine="redroid"
LABEL org.cubesandbox.instance_type="cubebox"
LABEL org.cubesandbox.runtime_model="cubevm-redroid"
LABEL org.cubesandbox.envd.enabled="true"
LABEL org.cubesandbox.envd.port="49983"

ENV ENVD_PORT=49983

ENTRYPOINT ["/usr/local/bin/android-redroid-entrypoint.sh"]
