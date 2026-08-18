# syntax=docker/dockerfile:1.7
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# CubeSandbox Android workload image with envd for cubebox template flow.
# Wraps sandbox-android-redroid (ReDroid AOSP 16) and injects envd built for
# Android/bionic (GOOS=android). Do NOT copy envd from cubesandbox-base: that
# binary targets GOOS=linux and will not execute inside ReDroid.
#
# Build (on aarch64 host or buildx):
#   docker build --platform linux/arm64 \
#     -t cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-android-redroid-envd:16.0.0-arm64 .

ARG REDROID_BASE_IMAGE=sandbox-android-redroid:16.0.0-arm64
ARG ENVD_REF=2026.16
ARG GO_VERSION=1.25.4
ARG ENVD_UPSTREAM_REPO=https://github.com/e2b-dev/infra.git

FROM golang:${GO_VERSION}-bookworm AS envd-builder

ARG ENVD_REF
ARG ENVD_UPSTREAM_REPO

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --depth 1 --branch "${ENVD_REF}" "${ENVD_UPSTREAM_REPO}" infra

WORKDIR /src/infra/packages/envd

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    commit_sha="$(git -C /src/infra rev-parse --short HEAD)" \
    && echo "Building envd for android/arm64 from ${ENVD_UPSTREAM_REPO}@${ENVD_REF} (commit=${commit_sha})" \
    && CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
       go build -a \
           -ldflags "-X=main.commitSHA=${commit_sha} -s -w" \
           -o /out/envd \
           . \
    && chmod +x /out/envd

COPY envd-starter /src/envd-starter
WORKDIR /src/envd-starter

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
    go build -a -ldflags "-s -w" -o /out/envd-starter .

FROM ${REDROID_BASE_IMAGE}

COPY --from=envd-builder --chmod=755 /out/envd /usr/bin/envd
COPY --from=envd-builder --chmod=755 /out/envd-starter /usr/bin/envd-starter

COPY android-init/cube-envd.rc /vendor/etc/init/cube-envd.rc
COPY android-init/cube-envd.rc /system/etc/init/cube-envd.rc

COPY --chmod=755 android-redroid-entrypoint.sh /usr/local/bin/android-redroid-entrypoint.sh
COPY --chmod=755 start-cube-envd.sh /usr/bin/start-cube-envd.sh

LABEL org.opencontainers.image.title="CubeSandbox Android Sandbox (ReDroid AOSP 16 + envd)"
LABEL org.opencontainers.image.description="ReDroid Android 16 with android/bionic envd for cubebox templates on Kunpeng ARM64"
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
LABEL org.cubesandbox.envd.goos="android"
LABEL org.cubesandbox.adb.port="5555"
LABEL org.cubesandbox.control_plane="envd:49983,adb:5555"

ENV ENVD_PORT=49983
ENV ENVD_REF=${ENVD_REF}
ENV CUBESANDBOX_ADB_PORT=5555

# Dual control plane (Tencent Agent Runtime Mobile style):
#   - envd :49983  Cube SDK / template probe / commands.run / files.*
#   - adbd :5555   adb connect automation
EXPOSE 49983 5555

# Default ReDroid boot props; override at `docker run` / template create time.
CMD ["androidboot.redroid_width=1080", "androidboot.redroid_height=1920", "androidboot.redroid_dpi=480", "androidboot.redroid_gpu_mode=guest"]

# PID1: envd-starter daemonizes envd (-isnotfc) then exec /init; cube-envd.rc is backup.
ENTRYPOINT ["/usr/bin/envd-starter"]
