# CubeShim Android ReDroid Log-Forwarding Fix (aarch64)

## Problem

ReDroid on CubeVM (Kunpeng ARM64) may fail during Android boot with:

```text
JNI FatalError called: (system_server) Unsupported st_mode for FD N: FIFO
```

`init.svc.zygote` stays `restarting`; no `system_server`; ADB port 5555 never listens.

**Cause:** CubeShim always enabled `cube.container.log_forwarding=true`, so the agent
created inherited stdout/stderr **pipe (FIFO)** file descriptors into Android `init` → `zygote`.
Zygote aborts when forking `system_server` if unexpected FIFOs remain open.

## Fix

This build disables init log forwarding for Android/ReDroid workloads (OCI args containing
`androidboot.*` or `/init` + `redroid`).

## Contents

| File | Description |
|------|-------------|
| `bin/containerd-shim-cube-rs` | Patched shim binary (aarch64) |
| `install.sh` | Install script with backup |
| `INSTALL.md` | This file |

## Install (euler-arm / Kunpeng)

```bash
tar xzf cube-shim-android-log-forwarding-fix-aarch64-*.tar.gz
cd cube-shim-android-log-forwarding-fix-aarch64-*
sudo ./install.sh

# Restart cubelet so new sandboxes pick up the shim
sudo systemctl restart cubelet
```

Default install path: `/usr/local/services/cubetoolbox/cube-shim/bin/containerd-shim-cube-rs`

Also updates `/usr/local/bin/containerd-shim-cube-rs` if the symlink exists.

## Verify

1. Create a **new** sandbox from your ReDroid template (existing sandboxes keep old shim until recreated).
2. `cube-runtime login <sandbox-id>`
3. Inside guest:

```bash
APID=$(for p in /proc/[0-9]*; do tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q second_stage && echo "${p#/proc/}" && break; done)
nsenter -t $APID -m -p -u -i -- /system/bin/getprop init.svc.zygote 2>/dev/null
# expect: running

dmesg | grep -i 'Unsupported st_mode' | tail -3
# expect: no new lines
```

## Rollback

```bash
sudo cp /usr/local/services/cubetoolbox/cube-shim/bin/containerd-shim-cube-rs.bak.* \
        /usr/local/services/cubetoolbox/cube-shim/bin/containerd-shim-cube-rs
sudo systemctl restart cubelet
```

## Build info

- Target: `aarch64-unknown-linux-gnu`
- Profile: `release`
- Source: CubeShim `should_enable_container_log_forwarding()` patch
