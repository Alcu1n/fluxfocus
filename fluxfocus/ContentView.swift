// [IN]: SwiftUI, SwiftData queries, AppStore service, NFCManager, FamilyControls, WheelPickerKit, and local focus models / SwiftUI、SwiftData 查询、AppStore 服务、NFCManager、FamilyControls、WheelPickerKit 与本地专注模型
// [OUT]: Main tab UI, NFC write/read entry points, invocation routing, wheel-based session drafting, and Focus Shield settings / 主标签 UI、NFC 读写入口、invocation 路由、基于滚轮的会话编排与 Focus Shield 设置
// [POS]: Primary SwiftUI composition root for the full app experience / 完整应用体验的主要 SwiftUI 组合根
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI
import WheelPickerKit

struct ContentView: View {
    private enum RootTab: Hashable {
        case home
        case session
        case chain
        case precedent
        case settings
    }

    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var focusShieldController: FocusShieldController

    @StateObject private var nfcManager = NFCManager()
    @Query(sort: \FocusSession.startAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \Appointment.scheduledStartAt, order: .reverse) private var appointments: [Appointment]
    @Query(sort: \ChainNode.createdAt, order: .reverse) private var nodes: [ChainNode]
    @Query(sort: \ViolationEvent.createdAt, order: .reverse) private var violations: [ViolationEvent]
    @Query(sort: \PrecedentRule.createdAt, order: .reverse) private var rules: [PrecedentRule]
    @Query(sort: \Tag.createdAt, order: .reverse) private var tags: [Tag]
    @Query(sort: \ShieldPolicy.updatedAt, order: .reverse) private var policies: [ShieldPolicy]
    @Query(sort: \AppConfiguration.updatedAt, order: .reverse) private var configurations: [AppConfiguration]

    @State private var quickStartDraft = SessionDraft()
    @State private var showInvocationSheet = false
    @State private var previousScenePhaseName = "active"
    @State private var nfcAlert: NFCAlert?
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    draft: $quickStartDraft,
                    showInvocationSheet: $showInvocationSheet,
                    nfcManager: nfcManager,
                    sessions: sessions,
                    appointments: appointments,
                    violations: violations,
                    tags: tags,
                    policies: policies,
                    configurations: configurations,
                    handleTagTouch: handleTagTouch
                )
            }
            .tabItem {
                Label("首页", systemImage: "house.fill")
            }
            .tag(RootTab.home)

            NavigationStack {
                SessionView(
                    draft: $quickStartDraft,
                    sessions: sessions,
                    appointments: appointments,
                    nodes: nodes,
                    tags: tags,
                    policies: policies
                )
            }
            .tabItem {
                Label("会话", systemImage: "timer")
            }
            .tag(RootTab.session)

            NavigationStack {
                ChainsView(
                    sessions: sessions,
                    appointments: appointments,
                    nodes: nodes
                )
            }
            .tabItem {
                Label("链条", systemImage: "link")
            }
            .tag(RootTab.chain)

            NavigationStack {
                PrecedentsView(violations: violations, rules: rules)
            }
            .tabItem {
                Label("判例", systemImage: "scroll")
            }
            .tag(RootTab.precedent)

            NavigationStack {
                SettingsView(
                    nfcManager: nfcManager,
                    tags: tags,
                    policies: policies,
                    configurations: configurations,
                    writeCurrentTag: writeCurrentTag,
                    readCurrentTag: readCurrentTag
                )
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        .sheet(isPresented: $showInvocationSheet) {
            InvocationSheet(
                draft: $quickStartDraft,
                sessions: sessions,
                appointments: appointments,
                nodes: nodes,
                violations: violations,
                tags: tags,
                policies: policies
            )
        }
        .sheet(isPresented: .constant(pendingViolation != nil)) {
            if let pendingViolation {
                DecisionSheet(event: pendingViolation, sessions: sessions)
            }
        }
        .task {
            try? appStore.bootstrapIfNeeded(context: modelContext)
        }
        .task(id: shieldSyncKey) {
            syncFocusShield()
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            let oldName = previousScenePhaseName
            previousScenePhaseName = newValue.label
            try? appStore.simulateScenePhaseChange(
                from: oldName,
                to: newValue.label,
                sessions: sessions,
                context: modelContext
            )
        }
        .onOpenURL { url in
            handleInvocationURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                handleInvocationURL(url)
            }
        }
        .alert(item: $nfcAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private var pendingViolation: ViolationEvent? {
        violations.first(where: { $0.decisionStatus == .pending })
    }

    private var shieldSyncKey: String {
        let runningSession = appStore.runningSession(from: sessions)
        let policy = appStore.activeShieldPolicy(from: policies)
        return [
            runningSession?.id.uuidString ?? "none",
            runningSession?.shieldEnabled == true ? "session-on" : "session-off",
            policy?.id.uuidString ?? "policy-none",
            policy?.enabled == true ? "policy-on" : "policy-off",
            policy?.updatedAt.ISO8601Format() ?? "never"
        ].joined(separator: "|")
    }

    private func handleTagTouch() {
        nfcManager.beginInvocationScan { result in
            switch result {
            case .success(let payload):
                guard let url = payload.url else {
                    nfcAlert = NFCAlert(
                        title: "标签无效",
                        message: "读取到了 NFC 内容，但不是当前 App 可识别的 FluxFocus invocation URL。"
                    )
                    return
                }
                handleInvocationURL(url, physicalUID: payload.uidHex)

            case .failure(let error):
                nfcAlert = NFCAlert(title: "NFC 读取失败", message: error.localizedDescription)
            }
        }
    }

    private func syncFocusShield() {
        let runningSession = appStore.runningSession(from: sessions)
        let policy = appStore.activeShieldPolicy(from: policies)
        focusShieldController.restoreSelection(from: policy)
        focusShieldController.applyShield(
            isEnabled: policy?.enabled == true && runningSession?.shieldEnabled == true,
            isSessionRunning: runningSession != nil
        )
    }

    private func writeCurrentTag() {
        guard let activeTag = appStore.activeTag(from: tags),
              let configuration = appStore.activeConfiguration(from: configurations),
              let url = appStore.invocationURL(for: activeTag, configuration: configuration) else {
            nfcAlert = NFCAlert(title: "无法写入", message: "请先在设置页配置 invocation host，并确认已有当前标签。")
            return
        }

        nfcManager.beginWrite(url: url) { result in
            switch result {
            case .success(let payload):
                try? appStore.bindPhysicalTag(activeTag, uidHex: payload.uidHex, context: modelContext)
                nfcAlert = NFCAlert(
                    title: "写入成功",
                    message: "已将以下 URL 写入 NFC 标签：\n\(url.absoluteString)"
                )
            case .failure(let error):
                nfcAlert = NFCAlert(title: "写入失败", message: error.localizedDescription)
            }
        }
    }

    private func readCurrentTag() {
        nfcManager.beginRawRead { result in
            switch result {
            case .success(let payload):
                let details = payload.rawRecords.joined(separator: "\n")
                nfcAlert = NFCAlert(
                    title: "标签内容",
                    message: "UID: \(payload.uidHex)\n\(details)"
                )
            case .failure(let error):
                nfcAlert = NFCAlert(title: "读取失败", message: error.localizedDescription)
            }
        }
    }

    private func handleInvocationURL(_ url: URL, physicalUID: String? = nil) {
        guard let route = appStore.parseInvocationRoute(url),
              let tag = appStore.tag(for: route.publicId, tags: tags) else {
            nfcAlert = NFCAlert(
                title: "标签无效",
                message: "读取到了 NFC 内容，但不是当前 App 可识别的 FluxFocus invocation URL。"
            )
            return
        }

        if let clipDurationMinutes = route.clipDurationMinutes {
            quickStartDraft.durationMinutes = max(5, clipDurationMinutes)
        }

        if let physicalUID {
            try? appStore.bindPhysicalTag(tag, uidHex: physicalUID, context: modelContext)
        }
        if tag.status != .active {
            try? appStore.activateTag(tag, tags: tags, context: modelContext)
        }

        if appStore.runningSession(from: sessions) != nil {
            selectedTab = .session
            return
        }

        try? appStore.startSession(
            draft: quickStartDraft,
            tag: tag,
            sessions: sessions,
            nodes: nodes,
            context: modelContext,
            source: .nfcInvocation
        )
        selectedTab = .session
    }
}

private struct NFCAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension ScenePhase {
    var label: String {
        switch self {
        case .active: "active"
        case .background: "background"
        case .inactive: "inactive"
        @unknown default: "unknown"
        }
    }
}

private struct HomeView: View {
    @Environment(AppStore.self) private var appStore

    @Binding var draft: SessionDraft
    @Binding var showInvocationSheet: Bool
    @ObservedObject var nfcManager: NFCManager

    let sessions: [FocusSession]
    let appointments: [Appointment]
    let violations: [ViolationEvent]
    let tags: [Tag]
    let policies: [ShieldPolicy]
    let configurations: [AppConfiguration]
    let handleTagTouch: () -> Void

    var body: some View {
        let metrics = appStore.metrics(
            sessions: sessions,
            appointments: appointments,
            violations: violations
        )
        let tag = appStore.activeTag(from: tags)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard(metrics: metrics, tag: tag)
                metricsGrid(metrics: metrics)
                reviewCard
            }
            .padding()
        }
        .navigationTitle("FluxFocus")
    }

    private func heroCard(metrics: DashboardMetrics, tag: Tag?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("触碰摆件，进入承诺场景")
                .font(.title2.bold())
            Text("当前 MVP 以本地规则引擎运行。这里接入真实 NFC / App Clip invocation，同时保留主链、预约链、判例与屏蔽策略。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Label(tag?.name ?? "未绑定标签", systemImage: "dot.radiowaves.left.and.right")
                Spacer()
                Text("主链 \(metrics.mainChainLength)")
                    .font(.headline.monospacedDigit())
            }
            .font(.footnote.weight(.medium))

            Button {
                handleTagTouch()
            } label: {
                Label("真实触碰 NFC 并进入专注流程", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let config = appStore.activeConfiguration(from: configurations) {
                Text("写入 host: \(config.invocationHost)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(nfcManager.statusMessage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.9), .blue.opacity(0.65), .mint.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .foregroundStyle(.white)
    }

    private func metricsGrid(metrics: DashboardMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "今日专注", value: metrics.focusSecondsToday.clockString, subtitle: "累计时长")
            MetricCard(title: "本周完成", value: "\(metrics.completedThisWeek)", subtitle: "完成会话")
            MetricCard(title: "预约链", value: "\(metrics.appointmentChainLength)", subtitle: "连续履约")
            MetricCard(title: "断链次数", value: "\(metrics.breakCount)", subtitle: "失败总数")
        }
    }

    private var reviewCard: some View {
        let latestFailure = violations.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("规则化复盘")
                .font(.headline)
            if let latestFailure {
                Text(latestFailure.type.label)
                    .font(.subheadline.weight(.semibold))
                Text(latestFailure.type.suggestion)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有失败记录，先完成一次会话再观察判例。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct InvocationSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var draft: SessionDraft

    let sessions: [FocusSession]
    let appointments: [Appointment]
    let nodes: [ChainNode]
    let violations: [ViolationEvent]
    let tags: [Tag]
    let policies: [ShieldPolicy]

    var body: some View {
        NavigationStack {
            Form {
                Section("今日链条状态") {
                    let metrics = appStore.metrics(
                        sessions: sessions,
                        appointments: appointments,
                        violations: violations
                    )
                    LabeledContent("主链") { Text("\(metrics.mainChainLength)") }
                    LabeledContent("预约链") { Text("\(metrics.appointmentChainLength)") }
                    LabeledContent("当前标签") { Text(appStore.activeTag(from: tags)?.name ?? "未绑定") }
                }

                SessionDraftForm(draft: $draft, policy: appStore.activeShieldPolicy(from: policies))

                Section {
                    Button("开始专注") {
                        startSession()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("15 分钟后开始") {
                        scheduleAppointment()
                    }
                }
            }
            .navigationTitle("进入专注模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func startSession() {
        guard let tag = appStore.activeTag(from: tags) else { return }
        try? appStore.startSession(
            draft: draft,
            tag: tag,
            sessions: sessions,
            nodes: nodes,
            context: modelContext,
            source: .nfcInvocation
        )
        dismiss()
    }

    private func scheduleAppointment() {
        guard let tag = appStore.activeTag(from: tags) else { return }
        _ = tag
        try? appStore.scheduleAppointment(draft: draft, tag: tag, context: modelContext)
        dismiss()
    }
}

private struct SessionView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext

    @Binding var draft: SessionDraft

    let sessions: [FocusSession]
    let appointments: [Appointment]
    let nodes: [ChainNode]
    let tags: [Tag]
    let policies: [ShieldPolicy]

    var body: some View {
        ZStack {
            SessionStudioBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    sessionHeader

                    if let activeSession {
                        runningStudio(activeSession)
                    } else {
                        draftStudio
                    }

                    if let pendingAppointment {
                        appointmentStudio(pendingAppointment)
                    }

                    recentSessionsStudio
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var activeSession: FocusSession? {
        appStore.runningSession(from: sessions)
    }

    private var pendingAppointment: Appointment? {
        appStore.scheduledAppointment(from: appointments)
    }

    private var activeShieldPolicy: ShieldPolicy? {
        appStore.activeShieldPolicy(from: policies)
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activeSession == nil ? "Focus Session" : "Session In Motion")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(.white.opacity(0.58))

            Text(activeSession?.goal ?? "把时长拨准，再安静地开始。")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(activeSession == nil ? "新的时间轮负责主节奏，下面只保留真正影响专注质量的设置。" : "当前会话正在运行。完成、标记不合格或主动退出，都在这里处理。")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var draftStudio: some View {
        VStack(spacing: 18) {
            SessionStudioCard {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        studioLabel("Duration")

                        Text("\(draft.durationMinutes) 分钟")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .monospacedDigit()
                    }

                    TimerWheelPicker(
                        selection: $draft.durationMinutes,
                        range: 5...180,
                        step: 5,
                        style: SessionStudioTheme.wheelStyle
                    )
                    .frame(maxWidth: .infinity)

                    Text("\(draft.durationMinutes) min")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.1), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
            }

            SessionStudioCard {
                VStack(alignment: .leading, spacing: 16) {
                    studioLabel("目标")

                    TextField("这段专注要产出什么？", text: $draft.goal)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }

                    shieldComposer
                }
            }

            HStack(spacing: 14) {
                SessionActionButton(
                    title: "立即开始",
                    subtitle: "主链会话",
                    tint: SessionStudioTheme.accent,
                    foreground: SessionStudioTheme.deepInk,
                    action: startQuickSession
                )

                SessionActionButton(
                    title: "预约 15 分钟后",
                    subtitle: "保留开始窗口",
                    tint: .white.opacity(0.08),
                    foreground: .white,
                    action: scheduleAppointment
                )
            }
        }
    }

    private var shieldComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    studioLabel("Focus Shield")
                    Text(draft.shieldEnabled ? "会话启动时应用系统屏蔽" : "这次会话不应用系统屏蔽")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Toggle("", isOn: $draft.shieldEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SessionStudioTheme.accent)
            }

            if draft.shieldEnabled {
                if let activeShieldPolicy, activeShieldPolicy.selectedApps.isEmpty == false {
                    SessionChipRow(values: Array(activeShieldPolicy.selectedApps.prefix(4)))
                    Text(activeShieldPolicy.selectedApps.count > 4 ? "已选 \(activeShieldPolicy.selectedApps.count) 项，完整列表在设置页维护。" : "已连接设置页中的真实屏蔽策略。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                } else {
                    Text("还没有可用的屏蔽目标。请先去设置页选择要拦截的 App 与网站。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
        }
        .padding(18)
        .background(SessionStudioTheme.panelStrong.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func runningStudio(_ activeSession: FocusSession) -> some View {
        SessionStudioCard {
            VStack(alignment: .leading, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, activeSession.durationSec - Int(context.date.timeIntervalSince(activeSession.startAt)))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SessionPill(title: activeSession.source.label)
                            SessionPill(title: activeSession.tagName)
                            if activeSession.shieldEnabled {
                                SessionPill(title: "Shield On", filled: true)
                            }
                        }

                        Text(remaining.clockString)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        Text("开始于 \(activeSession.startAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }

                if activeSession.shieldEnabled {
                    shieldRuntimePanel(activeSession)
                }

                VStack(spacing: 12) {
                    SessionActionButton(
                        title: "完成会话",
                        subtitle: "提交主链节点",
                        tint: SessionStudioTheme.accent,
                        foreground: SessionStudioTheme.deepInk
                    ) {
                        try? appStore.completeSession(
                            activeSession,
                            sessions: sessions,
                            nodes: nodes,
                            context: modelContext
                        )
                    }

                    HStack(spacing: 12) {
                        SessionActionButton(
                            title: "标记不合格",
                            subtitle: "记录质量失败",
                            tint: .white.opacity(0.08),
                            foreground: .white
                        ) {
                            try? appStore.recordQualityFailure(activeSession, context: modelContext)
                        }

                        SessionActionButton(
                            title: "退出",
                            subtitle: "终止当前会话",
                            tint: Color(red: 0.45, green: 0.17, blue: 0.18),
                            foreground: .white
                        ) {
                            try? appStore.abandonSession(activeSession, context: modelContext)
                        }
                    }
                }
            }
        }
    }

    private func shieldRuntimePanel(_ activeSession: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            studioLabel("Shield Runtime")

            Text(activeShieldPolicy?.selectedApps.joined(separator: " · ") ?? "未配置屏蔽目标")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let activeShieldPolicy, activeShieldPolicy.selectedApps.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeShieldPolicy.selectedApps, id: \.self) { app in
                            Button(app) {
                                try? appStore.simulateBlockedAppAttempt(
                                    appName: app,
                                    session: activeSession,
                                    context: modelContext
                                )
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.08), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(SessionStudioTheme.panelStrong.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func appointmentStudio(_ appointment: Appointment) -> some View {
        SessionStudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    studioLabel("当前预约链")
                    Spacer()
                    SessionPill(title: "Window")
                }

                Text(appointment.goal)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("开始于 \(appointment.scheduledStartAt.formatted(date: .omitted, time: .shortened))，窗口截止 \(appointment.windowEndAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                SessionActionButton(
                    title: "履约并开始",
                    subtitle: "接入主链",
                    tint: .white.opacity(0.08),
                    foreground: .white
                ) {
                    fulfillAppointment(appointment)
                }
            }
        }
    }

    private var recentSessionsStudio: some View {
        SessionStudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    studioLabel("最近会话")
                    Spacer()
                    Text("\(sessions.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                }

                if sessions.isEmpty {
                    Text("还没有会话记录。开始第一段高质量专注，历史才有意义。")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(sessions.prefix(6)), id: \.id) { session in
                            SessionRow(session: session)
                        }
                    }
                }
            }
        }
    }

    private func studioLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(.white.opacity(0.48))
    }

    private func startQuickSession() {
        guard let tag = appStore.activeTag(from: tags) else { return }
        try? appStore.startSession(
            draft: draft,
            tag: tag,
            sessions: sessions,
            nodes: nodes,
            context: modelContext,
            source: .quickStart
        )
    }

    private func scheduleAppointment() {
        guard let tag = appStore.activeTag(from: tags) else { return }
        try? appStore.scheduleAppointment(draft: draft, tag: tag, context: modelContext)
    }

    private func fulfillAppointment(_ appointment: Appointment) {
        guard let tag = appStore.activeTag(from: tags) else { return }
        let appointmentDraft = SessionDraft(
            goal: appointment.goal,
            durationMinutes: max(5, appointment.durationSec / 60),
            shieldEnabled: draft.shieldEnabled
        )
        try? appStore.startSession(
            draft: appointmentDraft,
            tag: tag,
            sessions: sessions,
            nodes: nodes,
            context: modelContext,
            source: .appointment,
            appointment: appointment
        )
    }
}

private enum SessionStudioTheme {
    static let deepInk = Color(red: 0.08, green: 0.12, blue: 0.19)
    static let deepForest = Color(red: 0.10, green: 0.21, blue: 0.18)
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.07)
    static let accent = Color(hue: 0.36, saturation: 0.58, brightness: 0.88)
    static let wheelStyle = TimerWheelPickerStyle(
        colors: .init(
            activeTint: .white,
            inactiveTint: Color.white.opacity(0.12),
            ringBackground: accent,
            tickGradient: Gradient(colors: [
                Color(hue: 0.57, saturation: 0.46, brightness: 0.86),
                Color(hue: 0.66, saturation: 0.82, brightness: 0.94)
            ]),
            valueGradient: Gradient(colors: [
                Color(hue: 0.48, saturation: 0.45, brightness: 0.88),
                Color(hue: 0.51, saturation: 0.62, brightness: 0.97)
            ])
        ),
        layout: .init(
            dialHeight: 214,
            dialScale: 0.9,
            ringThickness: 44,
            ringBackgroundExtraWidth: 10,
            indicatorHeight: 28,
            indicatorWidth: 5,
            indicatorDotSize: 10,
            tickWidth: 3.3,
            tickSlotWidth: 5.2,
            gapBetweenTicks: -2.6,
            largeTickFrequency: 3,
            largeTickRatio: 0.68,
            smallTickRatio: 0.32
        ),
        typography: .init(
            valueFontSize: 66,
            unitFontSize: 14,
            unitLabel: "MIN"
        )
    )
}

private struct SessionStudioBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SessionStudioTheme.deepInk,
                    Color(red: 0.11, green: 0.18, blue: 0.24),
                    SessionStudioTheme.deepForest
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    SessionStudioTheme.accent.opacity(0.30),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .blur(radius: 26)
        }
        .ignoresSafeArea()
    }
}

private struct SessionStudioCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(SessionStudioTheme.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 16)
    }
}

private struct SessionActionButton: View {
    let title: String
    let subtitle: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.74))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(foreground == .white ? 0.08 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }
}

private struct SessionChipRow: View {
    let values: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
            }
        }
    }
}

private struct SessionPill: View {
    let title: String
    var filled = false

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? SessionStudioTheme.deepInk : .white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                filled ? AnyShapeStyle(SessionStudioTheme.accent) : AnyShapeStyle(.white.opacity(0.07)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(filled ? 0 : 0.08), lineWidth: 1)
            }
    }
}

private struct ChainsView: View {
    let sessions: [FocusSession]
    let appointments: [Appointment]
    let nodes: [ChainNode]

    var body: some View {
        List {
            Section("主链节点") {
                if nodes.filter({ $0.chainType == .main }).isEmpty {
                    Text("暂无主链节点")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nodes.filter { $0.chainType == .main }, id: \.id) { node in
                        ChainNodeRow(node: node)
                    }
                }
            }

            Section("预约链节点") {
                if nodes.filter({ $0.chainType == .appointment }).isEmpty {
                    Text("暂无预约链节点")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nodes.filter { $0.chainType == .appointment }, id: \.id) { node in
                        ChainNodeRow(node: node)
                    }
                }
            }

            Section("失败记录") {
                let failedSessions = sessions.filter { $0.status == .failed }
                let missedAppointments = appointments.filter { $0.status == .missed }

                if failedSessions.isEmpty && missedAppointments.isEmpty {
                    Text("还没有断链事件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(failedSessions, id: \.id) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.goal)
                            Text(session.failedReason ?? "未知失败")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(missedAppointments, id: \.id) { appointment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appointment.goal)
                            Text("预约未履约")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("链条")
    }
}

private struct PrecedentsView: View {
    let violations: [ViolationEvent]
    let rules: [PrecedentRule]

    var body: some View {
        List {
            Section("违规事件") {
                if violations.isEmpty {
                    Text("暂无违规事件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(violations, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(event.type.label)
                                    .font(.headline)
                                Spacer()
                                Text(event.decisionStatus.rawValue)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(event.decisionStatus == .pending ? .orange : .secondary)
                            }
                            Text(event.payload)
                                .font(.subheadline)
                            Text(event.type.suggestion)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("生效规则") {
                if rules.isEmpty {
                    Text("暂无判例规则")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules, id: \.id) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(rule.violationType.label) · \(rule.decision.label)")
                            Text(rule.note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("判例")
    }
}

private struct SettingsView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focusShieldController: FocusShieldController

    @ObservedObject var nfcManager: NFCManager
    let tags: [Tag]
    let policies: [ShieldPolicy]
    let configurations: [AppConfiguration]
    let writeCurrentTag: () -> Void
    let readCurrentTag: () -> Void

    @State private var newTagName = ""

    var body: some View {
        List {
            Section("NFC 标签管理") {
                ForEach(tags, id: \.id) { tag in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tag.name)
                            Text(tag.tagPublicId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if tag.status == .active {
                            Text("当前")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.15), in: Capsule())
                        } else {
                            Button("设为当前") {
                                try? appStore.activateTag(tag, tags: tags, context: modelContext)
                            }
                        }
                    }
                }
                HStack {
                    TextField("新增标签名称", text: $newTagName)
                    Button("添加") {
                        try? appStore.addTag(name: newTagName, context: modelContext)
                        newTagName = ""
                    }
                }
            }

            if let configuration = appStore.activeConfiguration(from: configurations) {
                Section("NFC 写码") {
                    TextField("Invocation Host", text: Binding(
                        get: { configuration.invocationHost },
                        set: { try? appStore.updateInvocationHost(configuration, host: $0, context: modelContext) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if let activeTag = appStore.activeTag(from: tags),
                       let url = appStore.invocationURL(for: activeTag, configuration: configuration) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前写入 URL")
                                .font(.footnote.weight(.semibold))
                            Text(url.absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("写入当前标签到 NFC") {
                        writeCurrentTag()
                    }
                    Button("读取 NFC 标签内容") {
                        readCurrentTag()
                    }
                    Text(nfcManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("App Clip 调试") {
                    if let experienceURL = appStore.appClipExperienceURL(for: configuration) {
                        LabeledContent("Connect Experience URL") {
                            Text(experienceURL.absoluteString)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if let activeTag = appStore.activeTag(from: tags),
                       let url = appStore.invocationURL(for: activeTag, configuration: configuration) {
                        LabeledContent("Invocation URL") {
                            Text(url.absoluteString)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("AASA") {
                            Text("https://\(configuration.invocationHost)/.well-known/apple-app-site-association")
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("真机调试要点")
                            .font(.footnote.weight(.semibold))
                        Text("1. App Store Connect 中的 App Clip Experience URL 使用短地址 https://\(configuration.invocationHost)；物理 NFC 标签写入当前显示的 Invocation URL。")
                        Text("2. 每张 NFC 标签可以各自写入不同的 /i/<tagId>，不需要在 Connect 里逐条注册。")
                        Text("3. 若设备已安装完整 App，点卡片的“打开”后 invocation 会交给完整 App 继续。")
                        Text("4. 如果你之前在 设置 > Developer > Local Experiences 注册过本地体验，测线上链路前先删除它。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let policy = appStore.activeShieldPolicy(from: policies) {
                FocusShieldSection(policy: policy)
            }
        }
        .navigationTitle("设置")
    }
}

private struct FocusShieldSection: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focusShieldController: FocusShieldController

    let policy: ShieldPolicy

    var body: some View {
        Section("Focus Shield") {
            Toggle("启用专注期屏蔽", isOn: shieldEnabledBinding)

            Button("选择屏蔽 App 与网站") {
                Task {
                    _ = await focusShieldController.beginSelectionFlow()
                }
            }

            selectedSummaryRow
            tokenSection("已选 App", tokens: focusShieldController.selectedApplicationTokens)
            tokenSection("已选分类", tokens: focusShieldController.selectedCategoryTokens)
            tokenSection("已选网站", tokens: focusShieldController.selectedWebDomainTokens)

            Text(statusCopy)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastErrorMessage = focusShieldController.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .familyActivityPicker(
            isPresented: $focusShieldController.isPickerPresented,
            selection: $focusShieldController.activitySelection
        )
        .task(id: policy.updatedAt) {
            focusShieldController.restoreSelection(from: policy)
        }
        .onChange(of: focusShieldController.activitySelection) { _, _ in
            persistShieldSelection()
        }
    }

    private var shieldEnabledBinding: Binding<Bool> {
        Binding(
            get: { policy.enabled },
            set: { newValue in
                Task {
                    await handleShieldEnabledChange(newValue)
                }
            }
        )
    }

    @ViewBuilder
    private var selectedSummaryRow: some View {
        if policy.activitySelectionData != nil || focusShieldController.selectionSummary.isEmpty == false {
            LabeledContent("已选项目") {
                Text(summaryText)
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
        } else {
            Text("尚未选择任何 App、分类或网站。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryText: String {
        let summary = focusShieldController.selectionSummary.joined(separator: " · ")
        return summary.isEmpty ? "已保存选择" : summary
    }

    private var statusCopy: String {
        switch focusShieldController.authorizationStatus {
        case .approved:
            "Family Controls 已授权。选择的项目会在启用 Focus Shield 且会话进行中时被真实屏蔽。"
        case .denied:
            "Family Controls 已被拒绝。请在系统设置中重新授权。"
        case .notDetermined:
            "首次启用时会弹出系统授权与选择器。"
        @unknown default:
            "Family Controls 状态未知，请重新进入此页面确认授权。"
        }
    }

    @ViewBuilder
    private func tokenSection(_ title: String, tokens: [ActivityCategoryToken]) -> some View {
        if tokens.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tokenSection(_ title: String, tokens: [WebDomainToken]) -> some View {
        if tokens.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tokenSection(_ title: String, tokens: [ApplicationToken]) -> some View {
        if tokens.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func handleShieldEnabledChange(_ isEnabled: Bool) async {
        if isEnabled {
            let isAuthorized = await focusShieldController.requestAuthorizationIfNeeded()
            guard isAuthorized else {
                try? appStore.updateShieldEnabled(policy: policy, enabled: false, context: modelContext)
                return
            }

            try? appStore.updateShieldEnabled(policy: policy, enabled: true, context: modelContext)
            focusShieldController.restoreSelection(from: policy)
            if policy.activitySelectionData == nil && focusShieldController.selectionSummary.isEmpty {
                focusShieldController.isPickerPresented = true
            }
            return
        }

        try? appStore.updateShieldEnabled(policy: policy, enabled: false, context: modelContext)
        focusShieldController.clearShield()
    }

    private func persistShieldSelection() {
        try? appStore.updateShieldActivitySelection(
            policy: policy,
            encodedSelection: focusShieldController.persistableSelectionData(),
            summary: focusShieldController.selectionSummary,
            context: modelContext
        )
    }
}

private struct DecisionSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: ViolationEvent
    let sessions: [FocusSession]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.type.label)
                    .font(.title2.bold())
                Text(event.payload)
                    .foregroundStyle(.secondary)
                Text("每次违规必须二选一：断链重置，或者永久允许同类行为。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("断链重置") {
                    apply(.reset)
                }
                .buttonStyle(.borderedProminent)

                Button("永久允许该类行为") {
                    apply(.allowForever)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("下必为例")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func apply(_ decision: PrecedentDecision) {
        try? appStore.applyDecision(
            event: event,
            decision: decision,
            sessions: sessions,
            context: modelContext
        )
        dismiss()
    }
}

private struct SessionDraftForm: View {
    @Binding var draft: SessionDraft
    let policy: ShieldPolicy?

    var body: some View {
        Section("会话配置") {
            TextField("目标", text: $draft.goal)
            Stepper(value: $draft.durationMinutes, in: 5...120, step: 5) {
                LabeledContent("时长") {
                    Text("\(draft.durationMinutes) 分钟")
                }
            }
            Toggle("启用 Focus Shield", isOn: $draft.shieldEnabled)
            if draft.shieldEnabled {
                Text(policy?.selectedApps.joined(separator: "、") ?? "请先在设置页配置屏蔽 App")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(statusTint.opacity(0.22))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: statusIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(statusTint)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(session.goal)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(session.source.label) · \(session.durationSec.clockString)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(session.status.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(statusTint)
                Text(session.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusTint: Color {
        switch session.status {
        case .completed:
            SessionStudioTheme.accent
        case .failed:
            Color(red: 0.93, green: 0.43, blue: 0.43)
        case .running:
            Color(red: 0.47, green: 0.78, blue: 0.96)
        default:
            .white
        }
    }

    private var statusIcon: String {
        switch session.status {
        case .completed:
            "checkmark"
        case .failed:
            "xmark"
        case .running:
            "timer"
        default:
            "circle"
        }
    }
}

private struct ChainNodeRow: View {
    let node: ChainNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(node.chainType.label) #\(node.nodeIndex)")
                    .font(.headline)
                Spacer()
                Text(node.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(node.summary)
                .font(.subheadline)
            Text(node.proofHash.prefix(18) + "...")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
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
    ContentView()
        .environment(AppStore())
        .modelContainer(for: [
            Tag.self,
            FocusSession.self,
            Appointment.self,
            ChainNode.self,
            ViolationEvent.self,
            PrecedentRule.self,
            ShieldPolicy.self,
            AppConfiguration.self
        ], inMemory: true)
}
