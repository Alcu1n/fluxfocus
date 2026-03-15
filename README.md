# FluxFocus

FluxFocus is an iOS focus product that turns an NFC touch into an App Clip card, a full-app focus session, and a real Screen Time shield.  
FluxFocus 是一款 iOS 专注产品，把一次 NFC 触碰转化为 App Clip 卡片、完整 App 专注会话，以及真实的屏幕使用时间屏蔽。

## Structure / 结构

```text
.
├── fluxfocus/              Full app SwiftUI + SwiftData runtime / 完整 App 运行时
├── fluxfocusTests/         In-memory domain tests for NFC lifecycle rules / NFC 生命周期规则的内存内领域测试
├── fluxfocusClip/          App Clip target and invocation UI / App Clip 目标与入口 UI
├── docs/                   GitHub Pages + AASA hosting files / GitHub Pages 与 AASA 托管文件
├── fluxfocus.xcodeproj/    Xcode project and target wiring / Xcode 工程与 target 连接
├── APPCLIP_DEPLOY.md       Deployment and App Store Connect notes / 部署与 Connect 配置说明
└── PRD.md                  Product requirements / 产品需求文档
```

## Core Boundary / 核心边界

- `fluxfocus/` owns local data, NFC read/write, invocation parsing, Family Controls authorization, and auto-starting focus sessions.  
  `fluxfocus/` 负责本地数据、NFC 读写、invocation 解析、Family Controls 授权，以及自动启动专注会话。
- `fluxfocusClip/` owns the lightweight App Clip landing flow and hands off to the installed app when needed.  
  `fluxfocusClip/` 负责轻量 App Clip 落地流程，并在需要时通过自定义 scheme 移交给已安装的完整 App。
- `docs/` owns public web assets required by Apple domain association.  
  `docs/` 负责 Apple 域名关联所需的公网静态资源。

## Focus Shield / 专注屏蔽

- The full app keeps `Family Controls` authorization and the global shield switch in Settings, but moves concrete app/category/domain selection into the session wheel card so the blocking target is chosen where the focus decision is made.  
  完整 App 把 `Family Controls` 授权与全局总开关保留在设置页，同时把具体的 App/分类/网站选择迁到会话时间轮主卡中，让屏蔽目标在真正做专注决策的地方完成。
- The shield picker now opens inside a custom FluxFocus studio sheet that wraps Apple’s `FamilyActivityPicker`, so the shell matches the app even though the protected selection list remains system-owned.  
  屏蔽选择器现在通过一层自定义的 FluxFocus studio 弹层承载 Apple 的 `FamilyActivityPicker`，因此外壳视觉能与应用统一，而受保护的选择列表仍由系统控件接管。
- The persisted `ShieldPolicy` stores both a compact summary and the encoded Apple selection payload so the picker state survives relaunches.  
  持久化的 `ShieldPolicy` 同时保存精简摘要和 Apple 的选择数据编码，以保证应用重启后仍能恢复选择器状态。

## Session Studio / 会话控制台

- The `Session` tab now collapses goal drafting, the `WheelPickerKit` timer dial, immediate start, and inline Focus Shield selection into one dense primary card, so the page stops scattering startup decisions across multiple panels.  
  `会话` 标签页现在把目标编辑、`WheelPickerKit` 时间轮、立即开始按钮和内联 Focus Shield 选择压进同一张高密度主卡里，不再把启动决策分散在多块面板之间。
- Running sessions, pending appointments, and recent history reuse the same dark glass card language so the whole screen stays calm and focused on the active decision.  
  进行中的会话、预约链和历史记录都复用同一套深色玻璃卡片语言，让整个页面保持安静，并把注意力集中在当前决策上。
- A running session no longer ends from a local tap: countdown zero moves it into `awaitingNFCCompletion`, foreground exit or completion is driven by an explicit in-app Core NFC scan, the scan button recovers immediately after cancellation, and there is no local "mark failed" escape hatch.  
  进行中的会话不再通过本地点按结束：倒计时归零后会进入 `awaitingNFCCompletion`，前台退出或完结由应用内显式 Core NFC 扫描驱动，取消扫描后按钮会立刻复位，并且不再保留本地“标记失败”的逃生口。

## Home Chain Showcase / 首页链条展示

- The home screen now reserves a dedicated chain-first module above the summary metrics, turning completed focus work into a visible chain theater with glowing links, 12-day momentum pulses, and immediate proof of continuity.  
  首页现在在摘要指标上方预留了独立的链条优先模块，用发光链节、12 天动量脉冲和即时连续性证明，把已完成专注直接转成可见的链条剧场。
- This surface is intentionally visual-first: users should feel the accumulated mass of finished sessions before reading any numbers, because the product treats chain growth as the core reinforcement loop rather than a secondary streak counter.  
  这个表面刻意以视觉优先：用户应先感受到已完成会话的累积重量，再去读数字，因为产品把链条增长视为核心强化回路，而不是附属的 streak 计数器。

## Invocation Protocol / Invocation 协议

- App Store Connect registers a short experience URL: `https://fluxfocusclip.lraitech.com`  
  App Store Connect 注册短 experience URL：`https://fluxfocusclip.lraitech.com`
- Each NFC tag stores a two-record NDEF payload whose first record must remain the short invocation URL under `/i/<tagPublicId>`, while the second record carries a compact non-authoritative chain snapshot.  
  每张 NFC 标签都写入双记录 NDEF 载荷，其中第 1 条必须保持 `/i/<tagPublicId>` 的短 invocation URL，第 2 条则保存紧凑、非权威的链条快照。
- The full app parses `tagPublicId`, activates the tag, starts focus when appropriate, and during active sessions treats the same physical tag as the only valid completion or manual-exit trigger.  
  完整 App 解析 `tagPublicId`、在合适时启动专注，并在会话活跃期间把同一张物理标签视为唯一有效的完结或主动退出触发器。
- In development-side installs, the Clip can hand off to the full app through `fluxfocus://focus/<tagPublicId>`.  
  在开发态侧载环境中，Clip 可通过 `fluxfocus://focus/<tagPublicId>` 移交到完整 App。
