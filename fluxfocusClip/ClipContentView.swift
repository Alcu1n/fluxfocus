//
//  ClipContentView.swift
//  fluxfocusClip
//
//  Created by Codex on 2026/3/13.
//

import SwiftUI

struct ClipLaunchContext: Equatable {
    let url: URL?
    let publicId: String?
    let isValidInvocation: Bool

    init(url: URL? = nil) {
        self.url = url
        if let url {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let pathParts = url.pathComponents.filter { $0 != "/" }
            let version = components?.queryItems?.first(where: { $0.name == "v" })?.value
            let publicId = pathParts.count >= 2 && pathParts[0] == "i" ? pathParts[1] : nil
            self.publicId = publicId
            self.isValidInvocation = publicId != nil && version == "1"
        } else {
            self.publicId = nil
            self.isValidInvocation = false
        }
    }
}

struct ClipContentView: View {
    @Environment(\.openURL) private var openURL

    let context: ClipLaunchContext

    @State private var durationMinutes = 25
    @State private var shieldEnabled = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                invocationCard
                sessionConfigurator
                actions
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(
                LinearGradient(
                    colors: [.blue.opacity(0.12), .mint.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("FluxFocus Clip")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进入专注模式")
                .font(.largeTitle.bold())
            Text("App Clip 已接收到 NFC / Link invocation。用最少一步进入会话，再按需跳转完整 App。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var invocationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(context.isValidInvocation ? "Invocation 已识别" : "等待有效 invocation", systemImage: context.isValidInvocation ? "checkmark.seal.fill" : "questionmark.circle")
                .foregroundStyle(context.isValidInvocation ? .green : .orange)
            Text(context.publicId ?? "未解析到 tagPublicId")
                .font(.headline.monospaced())
            Text(context.url?.absoluteString ?? "尚未收到 URL")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var sessionConfigurator: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("时长 \(durationMinutes) 分钟", value: $durationMinutes, in: 5...60, step: 5)
            Toggle("启用 Focus Shield", isOn: $shieldEnabled)
            Text("MVP 中 App Clip 仅承接 invocation 和会话配置；真正的链条与屏蔽执行仍由完整 App 持久化。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button("在完整 App 中继续") {
                guard let url = context.url else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(context.url == nil)

            Button("打开默认 App Clip 链接") {
                guard let url = context.url else { return }
                openURL(url)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(context.url == nil)
        }
    }
}

#Preview {
    ClipContentView(
        context: ClipLaunchContext(
            url: URL(string: "https://fluxfocusclip.lraitech.com/i/desk-altar-001?v=1&s=demo")
        )
    )
}
