# FluxFocus

FluxFocus is an iOS focus product that turns an NFC touch into an App Clip card, a full-app focus session, and a real Screen Time shield.  
FluxFocus 是一款 iOS 专注产品，把一次 NFC 触碰转化为 App Clip 卡片、完整 App 专注会话，以及真实的屏幕使用时间屏蔽。

## Structure / 结构

```text
.
├── fluxfocus/              Full app SwiftUI + SwiftData runtime / 完整 App 运行时
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

- The full app requests `Family Controls` authorization, presents `FamilyActivityPicker`, persists the chosen selection, and applies `ManagedSettingsStore` only while a shielded session is running.  
  完整 App 会请求 `Family Controls` 授权、弹出 `FamilyActivityPicker`、持久化所选项目，并且只在开启屏蔽的运行中会话里应用 `ManagedSettingsStore`。
- The persisted `ShieldPolicy` stores both a compact summary and the encoded Apple selection payload so the picker state survives relaunches.  
  持久化的 `ShieldPolicy` 同时保存精简摘要和 Apple 的选择数据编码，以保证应用重启后仍能恢复选择器状态。

## Invocation Protocol / Invocation 协议

- App Store Connect registers a short experience URL: `https://fluxfocusclip.lraitech.com`  
  App Store Connect 注册短 experience URL：`https://fluxfocusclip.lraitech.com`
- Each NFC tag stores its own short invocation URL under `/i/<tagPublicId>`  
  每张 NFC 标签写入各自的短 invocation URL：`/i/<tagPublicId>`
- The full app parses `tagPublicId`, activates the tag, and starts focus immediately when appropriate.  
  完整 App 解析 `tagPublicId`，激活标签，并在合适时立即启动专注。
- In development-side installs, the Clip can hand off to the full app through `fluxfocus://focus/<tagPublicId>`.  
  在开发态侧载环境中，Clip 可通过 `fluxfocus://focus/<tagPublicId>` 移交到完整 App。
