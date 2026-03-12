//
//  FluxFocusClipApp.swift
//  fluxfocusClip
//
//  Created by Codex on 2026/3/13.
//

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
