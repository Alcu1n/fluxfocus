// [IN]: SwiftUI and the lightweight App Clip launch context model / SwiftUI 与轻量 App Clip 启动上下文模型
// [OUT]: App Clip scene bootstrap with URL and web-activity ingestion / 具备 URL 与网页活动摄入的 App Clip 场景启动器
// [POS]: Entry point for the App Clip target that keeps invocation parsing at the boundary / App Clip target 的入口点，并把 invocation 解析留在边界层
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI

@main
struct FluxFocusClipApp: App {
    @State private var launchContext = ClipLaunchContext()

    var body: some Scene {
        WindowGroup {
            ClipContentView(context: launchContext)
                .onOpenURL { url in
                    launchContext = ClipLaunchContext(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        launchContext = ClipLaunchContext(url: url)
                    }
                }
        }
    }
}
