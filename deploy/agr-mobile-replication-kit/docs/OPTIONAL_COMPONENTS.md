# 可选组件（AGR 有、本包 v1 未内置）

## Appium :4723

AGR 官方预置 Appium；鲲鹏复刻 v1 仅保证 **envd + adbd**。

后续可在 ReDroid 镜像内叠加：
- Node.js + Appium Server 2.x
- UiAutomator2 driver
- 模板 `--expose-port 4723`

客户端通过 CubeProxy `get_host(4723)` + envd access token 访问（与 AGR 文档一致）。

## ws-scrcpy :8000 / :8886

AGR 用于浏览器投屏。需在镜像内部署 ws-scrcpy 并暴露 8000。

## agr CLI 本地隧道

AGR 的 `agr instance mobile connect` 在**客户端**建隧道；CubeSandbox 侧用 **host_port 直连** 或自建 frp/ssh 隧道等价实现。

## android-world 适配层

AGR `android-world` 含 SmartRun `android_world_adapt` v23（SMS DB bootstrap、radio stub 等）。  
鲲鹏 ReDroid 16 副本**未包含**该闭源层；若需 Android World 基准任务，需自行预装 APK/脚本或等待 SmartRun 公开 arm64 镜像。
