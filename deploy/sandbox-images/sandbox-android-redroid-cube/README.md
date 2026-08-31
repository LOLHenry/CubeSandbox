# ReDroid + fd-sanitize-starter（CubeVM 冷启动验证）

在 **不改 cube-agent / shim** 的前提下，用镜像内 `ENTRYPOINT` 清理 rustjail 继承的 FIFO fd，再 `exec /init` 启动 ReDroid。

## 架构（一层）

```text
MicroVM Guest
  cube-agent (PID 1) ──rustjail──► OCI 容器
                                    │
                                    ▼
                          fd-sanitize-starter   ← 镜像 ENTRYPOINT
                            1. stdio → /dev/null
                            2. close fd >= 3
                            3. exec /init androidboot.*
                                    │
                                    ▼
                          ReDroid → zygote → system_server
```

日志：`/data/local/tmp/fd-sanitize-starter.log`（或 `/tmp/fd-sanitize-starter.log`）

---

## 第一步：在鲲鹏机上准备基础 ReDroid 镜像

若还没有 `sandbox-android-redroid:16.0.0-arm64`：

```bash
# 离线包 load 后 tag，或从上游 build
docker load -i cube-sandbox-android-kunpeng-arm64-docker-*.tar.gz
docker tag <loaded-id> sandbox-android-redroid:16.0.0-arm64

docker image inspect sandbox-android-redroid:16.0.0-arm64 --format '{{.Architecture}}'
# 必须 arm64
```

---

## 第二步：构建 fd-sanitize 镜像

在仓库根目录（或把本目录同步到 euler-arm-199）：

```bash
chmod +x deploy/sandbox-images/sandbox-android-redroid-cube/build.sh
./deploy/sandbox-images/sandbox-android-redroid-cube/build.sh
```

成功后会得到本地 tag：

```text
sandbox-android-redroid-cube:16.0.0-arm64
```

自检：

```bash
docker image inspect sandbox-android-redroid-cube:16.0.0-arm64 \
  --format 'entrypoint={{json .Config.Entrypoint}} arch={{.Architecture}}'
# entrypoint=["/usr/bin/fd-sanitize-starter"]  arch=arm64
```

---

## 第三步：（可选）确认 guest agent 为原版

本方案 **不依赖** agent 热修，但应用 **原版 v0.6 guest/shim** 做对照：

```bash
TOOLBOX=/usr/local/services/cubetoolbox
LOOP=$(sudo losetup --find --show --partscan "$TOOLBOX/cube-image/cube-guest-image-cpu.img")
PART="${LOOP}p1"; [[ -b "$PART" ]] || PART="$LOOP"
sudo mkdir -p /mnt/guest-check && sudo mount "$PART" /mnt/guest-check
/mnt/guest-check/sbin/init --version
sudo umount /mnt/guest-check; sudo losetup -d "$LOOP"
```

---

## 第四步：清理旧沙箱

```bash
cubemastercli list --all --wide --type cubebox
cubemastercli destroy <旧-sandbox-id>
```

---

## 第五步：冷启动（不用 tpl / AppSnapshot）

**前置：** 必须先 `tpl create-from-image`（或 `./prepare-cubelet-ext4.sh`），并把 multirun JSON 里的 `image` 改成 job 输出的 **`artifact_id`（`rfs-...`）**，不能继续用 Docker tag。示例 JSON 里的 `sandbox-android-redroid-cube:16.0.0-arm64` 只是源镜像名。

```bash
# 例：artifact_id=rfs-cbaa3e6bb0fdfe4e91e06fe8
ART=rfs-cbaa3e6bb0fdfe4e91e06fe8
ls -lh /usr/local/services/cubetoolbox/cubebox_os_image/${ART}/${ART}.ext4

sed "s|sandbox-android-redroid-cube:16.0.0-arm64|${ART}|" \
  examples/redroid-cold-fd-sanitize.json > /tmp/redroid-cold.json

cubemastercli multirun --norm /tmp/redroid-cold.json
```

记下返回的 `sandbox_id`，例如 `tpl-xxx_0` 或随机 id。

**不要** 在 JSON 里带 `cube.master.appsnapshot.template.id`。

---

## 第六步：验证

```bash
SID=<sandbox-id>
cubemastercli info -s "$SID" --wide

cube-runtime login "$SID"
```

在 guest 里：

```bash
# starter 是否跑过
cat /data/local/tmp/fd-sanitize-starter.log
# 期望：stdio redirected ... closed N inherited fd(s) ... exec "/init" ...

# 进 Android 命名空间
APID=$(for p in /proc/[0-9]*; do
  tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q second_stage && echo "${p#/proc/}" && break
done)

nsenter -t "$APID" -m -p -u -i -- getprop init.svc.zygote
nsenter -t "$APID" -m -p -u -i -- getprop sys.boot_completed

dmesg | grep -i 'Unsupported_st_mode' | tail -5
# 期望：无新 FIFO 行；zygote=running，boot_completed=1（需等待 1～3 分钟）
```

宿主机 ADB（若映射了 5555）：

```bash
adb connect <节点IP>:<映射端口>
adb shell getprop init.svc.zygote
```

---

## 第七步：结果怎么读

| 现象 | 含义 |
|------|------|
| log 有 `closed N inherited fd` 且 zygote **running** | 镜像侧 workaround 有效 |
| 仍有 `Unsupported st_mode ... FIFO` | 可能还有 fd 未清干净，或 stdio 以外路径；贴 log + dmesg |
| 冷启动 OK，tpl restore 仍 GIC 失败 | FIFO 与 GIC 是两条线，继续查快照/KVM |
| multirun 失败 | 查 CPU/内存≥4C/6GiB、镜像 arm64、cubelet 日志 |
| `pmem file ...ext4 not exist` / `annotations are empty` | ① 未跑 `create-from-image`；② **更常见**：JSON 里写了 Docker tag，但 ext4 实际在 `rfs-...` artifact 路径下，需改 JSON 的 `image` 字段 |

---

## 与 envd 版的关系

本镜像 **不含 envd**，只验证 **FIFO/zygote**。通过后可在 `sandbox-android-redroid-envd` 的 `envd-starter` **之前** 合并同样 sanitize 逻辑，或让 ENTRYPOINT 改为 `fd-sanitize-starter` 再 exec `envd-starter`。

---

## 文件说明

| 文件 | 作用 |
|------|------|
| `fd-sanitize-starter/main.go` | 清 fd + exec /init |
| `Dockerfile` | 多阶段构建 starter + ReDroid base |
| `build.sh` | 一键 build + tag |
| `examples/redroid-cold-fd-sanitize.json` | cubemastercli multirun 请求 |
