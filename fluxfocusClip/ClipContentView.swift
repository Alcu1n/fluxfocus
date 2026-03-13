// [IN]: SwiftUI, invocation URL payload, and lightweight local clip session state / SwiftUI、invocation URL 载荷与轻量 Clip 会话状态
// [OUT]: App Clip landing UI, invocation diagnostics, and optional local timer flow / App Clip 落地 UI、invocation 诊断与可选本地计时流程
// [POS]: Focus-first App Clip surface that can hand off to the installed full app / 可移交给已安装完整应用的专注优先 App Clip 界面
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI

struct ClipLaunchContext: Equatable {
    let url: URL?
    let publicId: String?
    let isValidInvocation: Bool

    init(url: URL? = nil) {
        self.url = url
        if let url {
            let pathParts = url.pathComponents.filter { $0 != "/" }
            let publicId = pathParts.count >= 2 && pathParts[0] == "i" ? pathParts[1] : nil
            self.publicId = publicId
            self.isValidInvocation = publicId != nil
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
    @State private var runningSession: ClipFocusSession?
    @State private var completedSession: ClipFocusSession?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                invocationCard
                if let runningSession {
                    runningCard(session: runningSession)
                } else if let completedSession {
                    completionCard(session: completedSession)
                } else {
                    sessionConfigurator
                }
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
            Text("App Clip 已接收到 NFC / Link invocation。先在 Clip 内进入会话，后续再按需跳转完整 App。")
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
            if context.isValidInvocation == false {
                Text("如果这是通过 NFC 真实触发的结果，先检查 Connect 里是否注册了短 Experience URL，并确认标签内容是 /i/<tagId> 这种短路径。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var sessionConfigurator: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("时长 \(durationMinutes) 分钟", value: $durationMinutes, in: 5...60, step: 5)
            Toggle("启用 Focus Shield", isOn: $shieldEnabled)
            Text("Clip 里会先启动一个轻量本地倒计时。真正的链条持久化和违规判例仍由完整 App 负责。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if runningSession == nil, completedSession == nil {
                Button("开始 \(durationMinutes) 分钟专注") {
                    startClipSession()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(context.isValidInvocation == false)
            }

            Button("在完整 App 中继续") {
                continueInFullApp()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(context.url == nil)

            Button("重新打开 invocation URL") {
                reopenInvocationURL()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(context.url == nil)
        }
    }

    private func runningCard(session: ClipFocusSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let elapsed = Int(timeline.date.timeIntervalSince(session.startedAt))
                let remaining = max(0, session.durationSeconds - elapsed)

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.title2.bold())
                    Text(remaining.clockString)
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(session.tagPublicId) · Focus Shield \(session.shieldEnabled ? "开启" : "关闭")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: remaining) { _, newValue in
                    if newValue == 0 {
                        finishClipSession()
                    }
                }
            }

            HStack {
                Button("提前完成") {
                    finishClipSession()
                }
                .buttonStyle(.borderedProminent)

                Button("放弃") {
                    abandonClipSession()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func completionCard(session: ClipFocusSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本次专注已完成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(session.title)
                .font(.title3.bold())
            Text("你已经在 Clip 内完成了一次 \(session.durationSeconds / 60) 分钟会话。接下来可以跳转完整 App，把这次触发纳入链条记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func startClipSession() {
        guard context.isValidInvocation, let publicId = context.publicId else { return }
        completedSession = nil
        runningSession = ClipFocusSession(
            tagPublicId: publicId,
            durationSeconds: durationMinutes * 60,
            shieldEnabled: shieldEnabled
        )
    }

    private func finishClipSession() {
        guard let runningSession else { return }
        completedSession = runningSession
        self.runningSession = nil
    }

    private func abandonClipSession() {
        runningSession = nil
        completedSession = nil
    }

    private func continueInFullApp() {
        guard let url = context.url else { return }
        openURL(continueURL(for: url))
    }

    private func reopenInvocationURL() {
        guard let url = context.url else { return }
        openURL(url)
    }

    private func continueURL(for url: URL) -> URL {
        guard completedSession != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "clip_completed" || $0.name == "clip_duration" }
        queryItems.append(URLQueryItem(name: "clip_completed", value: "1"))
        queryItems.append(URLQueryItem(name: "clip_duration", value: "\(durationMinutes)"))
        components.queryItems = queryItems
        return components.url ?? url
    }
}

private struct ClipFocusSession: Equatable {
    let tagPublicId: String
    let durationSeconds: Int
    let shieldEnabled: Bool
    let startedAt: Date = .now

    var title: String {
        "NFC 专注 \(durationSeconds / 60) 分钟"
    }
}

private extension Int {
    var clockString: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ClipContentView(
        context: ClipLaunchContext(
            url: URL(string: "https://fluxfocusclip.lraitech.com/i/desk-altar-001")
        )
    )
}
