# cube-agent Android ReDroid FD Sanitize Fix (aarch64)

## Problem

ReDroid on CubeVM (Kunpeng ARM64) may fail during Android boot with:

```text
JNI FatalError called: (system_server) Unsupported st_mode for FD N: FIFO
```

Guest checks:

- `init.svc.zygote` = `restarting`
- no `zygote64` / `system_server` processes
- `adbd` may run but port **5555** never listens

## Root cause

Two layers:

1. **Shim** may inject `cube.container.log_forwarding=true`, causing the agent to create
   inherited stdout/stderr **pipe (FIFO)** fds into Android `init` → `zygote`.
2. **Agent** also leaves the **exec.fifo sync fd** (and other fds >= 3) open across `exec("/init")`.
   Android ART aborts when `system_server` sees unexpected FIFO fds.

The shim-only hotfix is **necessary but not sufficient**. You need this **guest cube-agent**
build as well.

## Fix (agent)

- Force `log_forwarding=false` for Android/ReDroid OCI args (defense in depth).
- Close exec.fifo sync fd after the prestart handshake.
- Before `exec("/init")`, close all inherited fds >= 3 for Android workloads.

## Contents

| File | Description |
|------|-------------|
| `bin/cube-agent` | Patched guest agent binary (aarch64 musl static) |
| `install-guest-image.sh` | Replace `/sbin/init` inside `cube-guest-image-cpu.img` |
| `INSTALL.md` | This file |

## Download

```bash
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-agent-android-fd-sanitize-fix-aarch64/cube-agent-android-fd-sanitize-fix-aarch64-3c8c5a2.tar.gz
wget https://github.com/LOLHenry/CubeSandbox/releases/download/cube-agent-android-fd-sanitize-fix-aarch64/cube-agent-android-fd-sanitize-fix-aarch64-3c8c5a2.tar.gz.sha256
sha256sum -c cube-agent-android-fd-sanitize-fix-aarch64-3c8c5a2.tar.gz.sha256
```

SHA256: `b54d47bd20b5b4b61aefc2899c2b464a499ab53e0ba0487b9ab0db4ca8688bb5`

## Install (euler-arm / Kunpeng)

**Prerequisite:** install the matching shim hotfix first (see
`deploy/releases/cube-shim-android-log-forwarding-fix-aarch64/INSTALL.md`).

```bash
tar xzf cube-agent-android-fd-sanitize-fix-aarch64-*.tar.gz
cd cube-agent-android-fd-sanitize-fix-aarch64-*

# Default guest image path from one-click install:
sudo ./install-guest-image.sh

# Or specify image path explicitly:
sudo ./install-guest-image.sh /usr/local/services/cubetoolbox/cube-image/cube-guest-image-cpu.img

sudo systemctl restart cube-sandbox-cubelet.service
```

Start a **new** ReDroid sandbox after install (existing VMs keep the old agent).

## Verify

Inside the Android guest namespace (after `cube-runtime login`):

```bash
getprop init.svc.zygote
# expect: running

getprop sys.boot_completed
# expect: 1

for name in zygote64 system_server adbd; do
  echo -n "$name: "
  for p in /proc/[0-9]*; do
    tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q "$name" && echo -n "${p#/proc/} "
  done
  echo
done

dmesg | grep -i 'Unsupported st_mode' | tail -3
# expect: no new lines after fix
```

Host: `adb connect <node-ip>:<mapped-5555>` should succeed.

## Rollback

```bash
sudo cp /usr/local/services/cubetoolbox/cube-image/cube-guest-image-cpu.img.bak.* \
        /usr/local/services/cubetoolbox/cube-image/cube-guest-image-cpu.img
sudo systemctl restart cube-sandbox-cubelet.service
```

## Build info

- Target: `aarch64-unknown-linux-musl`
- Profile: `release`
- Binary in guest image: `/sbin/init` (cube-agent)
