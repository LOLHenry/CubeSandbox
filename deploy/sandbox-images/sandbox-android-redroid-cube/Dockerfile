# syntax=docker/dockerfile:1.7
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# ReDroid AOSP 16 with CubeVM inherited-FD sanitizer (no envd).
# Use for cold-start validation of zygote/FIFO on Kunpeng before layering envd.
#
# Build (aarch64):
#   ./deploy/sandbox-images/sandbox-android-redroid-cube/build.sh

ARG REDROID_BASE_IMAGE=sandbox-android-redroid:16.0.0-arm64
ARG GO_VERSION=1.25.4

FROM golang:${GO_VERSION}-bookworm AS fd-sanitize-builder

WORKDIR /src/fd-sanitize-starter
COPY fd-sanitize-starter/go.mod fd-sanitize-starter/main.go ./

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -ldflags "-s -w" -o /out/fd-sanitize-starter .

FROM ${REDROID_BASE_IMAGE}

COPY --from=fd-sanitize-builder --chmod=755 /out/fd-sanitize-starter /usr/bin/fd-sanitize-starter

LABEL org.opencontainers.image.title="CubeSandbox Android (ReDroid + FD sanitize)"
LABEL org.opencontainers.image.description="ReDroid 16 with fd-sanitize-starter for CubeVM FIFO workaround without cube-agent patch"
LABEL org.cubesandbox.sandbox.id="sandbox-android-kunpeng-arm64-fd-sanitize"
LABEL org.cubesandbox.sandbox.category="android"
LABEL org.cubesandbox.sandbox.platform="kunpeng-arm64"
LABEL org.cubesandbox.android.version="16"
LABEL org.cubesandbox.android.engine="redroid"
LABEL org.cubesandbox.runtime_model="cubevm-redroid-fd-sanitize"
LABEL org.cubesandbox.envd.enabled="false"

EXPOSE 5555

# Passed through to ReDroid /init as kernel cmdline-style args.
CMD ["androidboot.redroid_width=1080", \
     "androidboot.redroid_height=1920", \
     "androidboot.redroid_dpi=480", \
     "androidboot.redroid_gpu_mode=guest"]

# First process inside the OCI container (after rustjail exec).
ENTRYPOINT ["/usr/bin/fd-sanitize-starter"]
