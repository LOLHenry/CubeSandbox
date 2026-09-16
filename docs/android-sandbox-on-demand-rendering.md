# Android 沙箱渲染：按需高帧率（完整稿）

> 本页提出问题并给出技术诉求。实现仍在验证。按需 / 快速两条并行，分由不同团队承担。

## 标题

Android 沙箱：AI Agent 基础设施之一，诉求按需高帧率渲染

## 1. 背景：训练对沙箱要什么，现在差在哪

### 训练到底要沙箱干什么

Mobile GUI 训练不是「开一台模拟器给人看」，而是用很多台 Android 环境给模型采轨迹：每台循环 **截图 → 决策 → 点击/滑动**，采完一批就更新策略。沙箱要同时满足三件事：

1. **能并开：** 一次训练要同时挂一批 **Android** 环境。公开、真正在模拟器/沙箱里在线采轨迹的工作，2024 年常见 **几十路**（DistRL 32、DigiRL 最多 64，超过约 32 路就要多机）；2025 年 MobileRL 把 Docker AVD **稳定开到 256 路**（文中写过可交互 1000，自己又说内存/磁盘顶住、稳定上限 256）。MAI-UI 把 Docker AVD online RL **集群开到 512 路**（10 台 ECS），消融显示 32→512 才把 8B 从 65.5 拉到 70.7；这是多机调度容量，**不是单机装箱规格**。MobileGym 的 **96 / 256 路**是浏览器里的 JSON 模拟，不是 AVD/ReDroid，不能用来对标我们的 CPU 装箱。「数千台」出现在 UI-TARS-2 / UI-Venus 的 **Win/Ubuntu/Android 混部** 集群，**没有拆出 Android 占多少**。对标装箱是 **2 核/台**（DigiRL、MobileGUI-RL）。桌面 ARPO 的 256 路不要拿来当 Android 的数。
2. **能截图、能操作：** 观测就是屏幕图，动作就是坐标手势。人不需要 60fps 视频流；模型一步看一张图。
3. **采得起、供得上：** 环境路数乘采样吞吐。路数开不满，同样预算少做实验。

单条轨迹并不长：DigiRL 每条最多 **10～20 步**，MobileGUI-RL 最多 **25 步**，MAI-UI online RL 把单条环境步上限从 **15 拉到 50**（8B 上 +4.3 分），仍是几十步。评测任务几十到两百条量级。主流范式是 **「中短轨迹 × 多路并行 × 多轮迭代」**，不是「一轮 100 万步、100 路一起跑」。下面不用这个假算例。

### 现在存在的问题（实在讲）

我们这套 Android 沙箱是 MicroVM 里跑 ReDroid，`gpu_mode=guest`，画面走 **CPU 软渲染（SwiftShader）**。catalog 默认 **4 核 / 6GiB、1080×1920**。内部画像：复杂界面软渲染 **CPU 热点超过 50%**，部分场景 **帧率低于 10fps**。

具体就两件事：

- **截图时画得慢：** 模型要的是一张已经画完的图。帧率低于 10fps 时，凑齐这张图要多等。
- **不截图时还在画：** 决策（模型推理）往往占逐步大部分墙钟，此时没人看屏幕，合成仍按「给人看」的方式刷，CPU 继续烧。

对训练的实在后果：决策期屏幕无人看，合成还在刷，**CPU 被无效渲染占住**。全程 20fps 的实验里，同机并发可 **+20%～25%**；真实 Agent 循环截图仍要高帧，**这个密度兑现不了**。不能拿对标 2 核反推。

## 2. CPU 渲染对业务问题的影响（按真实训练规模量化）

### 2.1 非截图阶段：占用能写，密度 20%～25% 只是实验上限

决策往往占逐步大部分墙钟，此时不需要出给 Agent 的新帧，合成仍在刷。内部画像：复杂界面软渲染 **CPU 热点超过 50%**。这一条只证明 **无效渲染在吃核**。

密度不要用对标 2 核。catalog 4 核可能叠了 MicroVM / Android 常驻 / 1080p / 6GiB / 配额保守，**尚未拆开**。

自己测过：**整机刷新 60fps → 20fps，并发 +20%～25%。** 这是 **全程 20fps** 才拿到的数。实际使用不会这样跑：截图期仍要尽快出稳定帧（接近高帧或至少不能卡在 20fps），只有决策期才可以少刷或不刷。因此：

- 20%～25% 是「渲染刷新确实拖密度」的 **实验上限**，不是上线配方
- 截图仍高帧时，装箱若卡 **峰值 CPU**（截图那一下），决策期停刷几乎加不开路，兑现可以接近 **0**
- 装箱若卡 **平均 CPU**（超卖、看一段时间的核时），决策期占墙钟大部分，按需能吃到上限里的一块，但仍 **低于** 全程 20fps 的 20%～25%
- 未做「只在决策期降帧、截图期保持高帧」对照，**兑现密度不填百分数**

两条手段各自改哪一段：

- **按需：** 只切决策期无效刷新。密度贡献待测，不能抄 20%～25%。
- **快速：** 切截图期出帧。全程 20fps 会伤截图，本就不是生产手段。

**给决策的一句话：** 全程 20fps 能把密度抬 20%～25%，真实循环截图仍要高帧，这个数兑现不了；表上不要写成已经少开了 20%～25%。

### 2.2 次影响：截图多等 100ms～1s，不是主矛盾

&lt;10fps 时，稳定截图常常多等 **100ms～1s**。主流轨迹只有十几到二十几步，决策本身又是秒级，**单条轨迹多等几秒，对「人能不能用」几乎无感，也撑不起「训练体验差」这个帽子。**

它仍然值得做，原因不是 100ms，而是：复杂页若迟迟画不完，截图窗口会从百毫秒拖成数秒，并行池被慢环境拖尾。快速渲染要防的是这条尾，不是日常那 100ms。

### 2.3 对外填表口径

| 填空 | 可写的数 | 依据 | 不能写成 |
| --- | --- | --- | --- |
| 一轮 Rollout 时间增加 | **约 5%～15%**（推荐填 **约 10%**） | 见下方注释 | 50%、翻倍；也不是热点 50% 直接搬过来 |
| 非截图阶段占用 CPU | **超过 50%**（热点占比） | 内部画像，复杂界面软渲染 | 已等于密度百分数 |
| 单机并发密度变少 | **不填兑现值**；口头可说实验上限 20%～25% | 全程 20fps 才 +20%～25%；生产截图仍要高帧 | 已兑现 20%～25%；对标 2/4=50% |

一轮增幅与步数无关：ΔT/T = Δt_截图 / T_单步。注释：估算条件为中小模型推理、单步时延 2～3 s；依据是内部画像复杂界面 &lt;10fps，相对 60fps 稳定截图多等约 0.1～0.3 s（帧周期 100 ms vs 16.7 ms，按 1～2 帧），故一轮约增 5%～15%（取中约 10%）。

密度：20%～25% 只证明「刷新越快越吃核」，条件是 **全程 20fps**。真实循环是截图高帧 + 决策少刷，兑现 **低于该上限**；若配额按截图峰值核数定，按需几乎不加路。表上不要填 20%～25%。要兑现密度，做「决策期停刷、截图期保持高帧」对照。

## 3. 技术诉求：Android 哪一层 → 两条手段

不先拆清切哪一层，按需和快速会对不准团队。

**上面两层（不该画还在画）→ 按需渲染**

- **应用层：** 动画、WebView 仍在动。**不是所有渲染都走 Choreographer。** View / Compose 才走下面那条排帧；游戏、视频、相机、WebView 可自己往 Surface 送帧。只停排帧，停不掉这一路。
- **框架层：** View 主路径四步。**Choreographer** 排帧 → **ViewRootImpl** 重绘 → **HWUI** 发画令 → **SurfaceFlinger** 合成。不截图时这条链路仍在转。合成是出帧最后一步，不另列一层。

**最底层（画一帧太贵）→ 快速渲染**

- **图形驱动层：** 接 GLES 并填像素，来源可以是 HWUI，也可以是应用自己的 GL/Vulkan 线程。真机是 GPU。本沙箱 `gpu_mode=guest`，换成 **SwiftShader（CPU 冒充 GPU）**，热点在这里。
- 快速渲染改的是这一层：把 CPU 填像素加快。不改 App，也不改 HWUI。

由此只收两条手段（并行、分团队）：

1. **按需渲染：** 切应用 / 框架。应用少送帧（含自行送帧的 WebView / SurfaceView），框架少排、少合成。只钩 Choreographer 不够。能否降核用同节点实验回答。  
2. **快速渲染：** 切图形驱动层，把 CPU 软渲染画快，缩短出帧。

## 4. 软件栈图

上到下是 Android 图形栈。蓝 = 按需（应用 / 框架），橙 = 快速（驱动）。

![Android 图形栈：按需切应用和框架，快速切图形驱动层](assets/android-cpu-render-stack.png)

出一帧有两条路。下表是 **View / Compose 主路径**（Choreographer 驱动）：

| 步骤 | 模块 | 干什么 |
| --- | --- | --- |
| 排帧 | **Choreographer** | 接到 VSYNC 后决定这一帧现在走。**只驱动 View 界面，不是全部渲染** |
| 重绘 | **ViewRootImpl** | measure / layout / draw，记下怎么画，还不是像素 |
| 发画令 | **HWUI** | 系统自带的界面渲染器（`libhwui`）。把显示列表编成 GLES/Vulkan 发出去，不填像素 |
| 合成 | **SurfaceFlinger** | 多个窗口叠成一整屏；谁送来的缓冲都叠，不看是不是 Choreographer 送的 |
| 填像素 | **SwiftShader**（本沙箱） | 驱动层。执行 GLES（HWUI 或应用自己发），CPU 冒充 GPU。真机这一格是 GPU 驱动 |

另一条路：**应用自行送帧**。SurfaceView 游戏、视频解码、相机、WebView 内部合成器可以不经 Choreographer，自己往 Surface 送缓冲。Native 也可用 AChoreographer 跟同一路 VSYNC，或不等 VSYNC 狂 swap。按需如果只钩 Choreographer，这几路还在画。

## 依据（脚注，不入口号正文）

- DigiRL, NeurIPS 2024：最多 **64** 路 Android 模拟器 / 128 CPU（约 2 核一台）；单机硬堆 64 CPU 只有 0.74 traj/min，分布式 1.74；&gt;32 路需多机。  
- DistRL, 2024：2 台 96 vCPU worker，最多 **32** 路 Android 模拟器/真机。  
- MobileGUI-RL, 2025：AVD **2 核** / 3GiB；实例数随 batch；7B global batch 128，每任务 8 条 rollout，≤25 步。未写死并发路数。  
- MobileRL, 2025（清华 + Z.AI 实习，**不是腾讯**）：Limitation 原文：“the system can only stably sustain up to 256 parallel rollouts, with each step taking more than 10 minutes … training 100 steps already takes more than 25 hours … large-scale image inference and network transmission introduce significant overhead.” 这里的 step 是 **RL 训练步**（batch 256、每条最多 50 个 GUI turn），不是一次点击。前文又写过可 concurrent interaction with over 1,000 environments，与 limitation 的稳定 256 并列，不能只取 1000。  
- UI-Venus-1.5, 2026：DaaS 接数千异构设备；RL 写过数百～数千并发，**未拆 Android**。  
- UI-TARS-2, 2025：数千 VM（Win / Ubuntu / Android 混部），**未拆 Android 路数**。  
- PhoneBuddy / PhoneWorld, 2026（**腾讯混元**）：不是「只用真机」。PhoneBuddy real-app = **真机 + 真 App**（未公布真机台数）。PhoneWorld mock APK 跑在模拟器上：论文写死的 **Android 13 Pixel 6 × 6 台 + 3 路 vLLM 只是在线评测**，不是训练农场。PhoneWorld 主实验的「训练」是把已采轨迹拿去 LlamaFactory 做 SFT（Qwen3.5-9B，截图 1080×2400）；采轨迹写的是 Seed 2.0 Pro 在 emulator 上 rollout，**未写训练开了几台、几核、哪张 GPU**。开源 AVD 与 AndroidWorld 相同：Pixel 6 / API 33。AppAgent（腾讯 GY Lab, 2023）是 GPT-4V 探索式操作，不是大规模在线 RL。  
- MAI-UI, 2025（阿里通义 Tongyi-MAI，https://arxiv.org/abs/2512.22047）：backbone **Qwen3-VL**，四档 **2B / 8B / 32B / 235B-A22B**。四阶段：(i) 感知+grounding SFT → (ii) 导航 SFT（掺少量 grounding）→ (iii) grounding GRPO → (iv) 导航 **online RL**。SFT 语料规模、RL 训练步数/epoch、GPU 型号与卡时 **全文未写**。online RL 环境是 **Docker 封装的 rooted AVD**（不是真机、也不是 ReDroid），接入 **35+ App**；任务按当前策略 pass@K 分成四档课程（0–25 / 25–50 / 50–75 / 75–100），**未公布训练任务条数**。算法：verl 上严格 on-policy，异步 rollout；GRPO **group size 16**，DAPO 式 clip `ε_low=0.2 / ε_high=0.3`、无 KL、token-level loss；奖励 = 轨迹成功（规则或 MLLM judge，与人一致率 83%）+ 重复动作惩罚；失败组从 replay 补成功轨迹（每任务保留最近 8 条）。单条上限 `max_env_steps` 消融 **15 / 30 / 50**，主实验 **50 步**（8B：SFT 64.7 → 15 步 66.4 / 30 步 68.5 / 50 步 70.7）。并行环境消融 **32 → 512**（8B 65.5 → 70.7，摘要 +5.2）。环境侧原文：Environment Manager 协调 **10 台标准阿里云 ECS（ecs.ebmg5s.24xlarge）**，最多 **512** 路并行 rollout。**没有写 960 vCPU / 3840GB。** 该机型是弹性裸金属：每台 **2× Intel Xeon Platinum 8163**（Skylake，24 核/48 线程，2.5 GHz / 全核睿频 2.7 GHz），HT 后标 **96 vCPU / 384 GiB**。10 台 = 20 颗 CPU、480 物理核、**960 超线程**。512 路是 **Docker AVD 容器**，不是 512 台 4 核虚拟机。满铺均摊约 **1.88 线程/路、7.5 GiB/路**，和 DigiRL / MobileGUI-RL 的 **2 核** 同量级；同一集群还要跑 35+ 自建 App 后端。未公布单台 AVD 核数，512/10≈51 路/机不能反推 catalog。32→512 的 +5.2 是 8B 在 AndroidWorld 的 **最终成功率**（65.5→70.7）：论文归因探索多样性、少路会早饱和；32 路几乎贴着 SFT（64.7）。512 是他们 **集群并发上限 + 8B 主实验路数**，不是理论下限（64/128/256 没发表）。**不是**墙钟加速，也没做「总 rollout 相同、只改并行」对照。G=16 只约束「同一任务一次对比 16 条」；一次 on-policy 更新还要覆盖很多不同任务。他们是 rollout 一波就更新（verl 严格 on-policy），32 路每步只铺 2 个任务，不是先串行攒满 512 再更新。所以「32 路跑 16 轮 = 512 路」只在冻结策略、攒大 batch 时成立；那只是墙钟变慢，策略并不过时。论文没做这个对照。早饱和说的是 **每步只看见 2 个任务就更新**，不是串行采数把模型采旧了。720p vs 1080p 只有一句「效果相当、每步约快 50.1%」，**没有**分分辨率分数表，也 **没有** 整轮训练墙钟。540p 只写明显掉点。评测不要当成训练任务池：AndroidWorld **116 任务 / 20 App**；MobileWorld **201 任务**（GUI 116 + 用户交互 45 + MCP 40）。GitHub README 后来写的 100+ 真机、~10000 路、>100 步 **不在这篇 arXiv 里**，不要混用。  
- MobileGym, 2026（https://arxiv.org/abs/2605.26114，https://mobilegym.dev/）：**浏览器模拟**，不是 AVD。单机容量 256 路（约 400MB/实例，&lt;10% CPU，约 100GB RAM）。实际 GRPO 训练：**96 路**浏览器实例，单机 3×RTX Pro 6000，10 个训练 step。§5.3 把 MAI-UI 转述成 “10 bare-metal cloud servers (960 vCPUs, 3,840 GB RAM total) to reach 512 parallel Android-emulator instances”。**「裸金属 + 960/3840」是 MobileGym 的转述和换算**，不是 MAI-UI 原句。  
- 本沙箱：目录 4 核 / 6GiB，`gpu_mode=guest`；内部画像 CPU 热点 &gt;50%、部分场景 &lt;10fps。整机刷新 **60fps→20fps**，同机并发 **+20%～25%**，条件是 **全程 20fps**。生产截图仍要高帧，该密度 **兑现不了**；未分阶段，不能记成按需专属，也不能和对标 2 核的 50% 混用。
