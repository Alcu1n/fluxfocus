// [IN]: SwiftUI, SwiftData queries, AppStore service, NFCManager, FamilyControls, WheelPickerKit, StudioChrome, and local focus models / SwiftUI、SwiftData 查询、AppStore 服务、NFCManager、FamilyControls、WheelPickerKit、StudioChrome 与本地专注模型
// [OUT]: Unified studio-style tab UI, NFC entry points, invocation routing, minute-level session drafting, and Focus Shield settings / 统一 studio 风格的标签页 UI、NFC 入口、invocation 路由、分钟级会话编排与 Focus Shield 设置
// [POS]: Primary SwiftUI composition root for the full app experience and shared studio surfaces / 完整应用体验与共享 studio 视觉表面的主要 SwiftUI 组合根
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
        let policy = appStore.activeShieldPolicy(from: policies)
        let configuration = appStore.activeConfiguration(from: configurations)

        ZStack {
            StudioBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroCard(
                        metrics: metrics,
                        tag: tag,
                        policy: policy,
                        configuration: configuration
                    )
                    metricsGrid(metrics: metrics)
                    reviewCard(metrics: metrics)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .studioNavigationBar()
    }

    private func heroCard(
        metrics: DashboardMetrics,
        tag: Tag?,
        policy: ShieldPolicy?,
        configuration: AppConfiguration?
    ) -> some View {
        StudioCard(emphasis: true) {
            VStack(alignment: .leading, spacing: 18) {
                StudioSectionLabel(title: "Entry")

                Text("触碰摆件，进入承诺场景")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("首页只保留真正影响启动决策的状态：当前标签、主链长度、屏蔽配置与 NFC 入口。其余细节放到对应分区里。")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    StudioCapsuleLabel(title: tag?.name ?? "未绑定标签", tone: .accent)
                    StudioCapsuleLabel(title: "主链 \(metrics.mainChainLength)")
                    if policy?.enabled == true {
                        StudioCapsuleLabel(title: "Shield 已启用")
                    }
                }

                HStack(spacing: 14) {
                    StudioActionButton(
                        title: "真实触碰 NFC",
                        subtitle: "直接进入专注流程",
                        tone: .primary,
                        action: handleTagTouch
                    )

                    StudioActionButton(
                        title: "打开会话草稿",
                        subtitle: "\(draft.durationMinutes) 分钟 · 当前草稿",
                        tone: .secondary
                    ) {
                        showInvocationSheet = true
                    }
                }

                StudioInsetPanel {
                    if let configuration {
                        infoLine(title: "写入 Host", value: configuration.invocationHost)
                    }
                    infoLine(title: "NFC 状态", value: nfcManager.statusMessage)
                }
            }
        }
    }

    private func metricsGrid(metrics: DashboardMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "今日专注", value: metrics.focusSecondsToday.clockString, subtitle: "累计时长")
            MetricCard(title: "本周完成", value: "\(metrics.completedThisWeek)", subtitle: "完成会话")
            MetricCard(title: "预约链", value: "\(metrics.appointmentChainLength)", subtitle: "连续履约")
            MetricCard(title: "屏蔽拦截", value: "\(metrics.shieldBlocks)", subtitle: "阻止诱惑应用")
        }
    }

    private func reviewCard(metrics: DashboardMetrics) -> some View {
        let latestFailure = violations.first
        return StudioCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StudioSectionLabel(title: "Review")
                    Spacer()
                    StudioCapsuleLabel(title: "断链 \(metrics.breakCount)", tone: metrics.breakCount == 0 ? .neutral : .danger)
                }

                if let latestFailure {
                    Text(latestFailure.type.label)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                    Text(latestFailure.type.suggestion)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StudioEmptyState(
                        title: "还没有失败记录",
                        message: "先完成一次高质量会话，再看判例与断链建议。"
                    )
                }
            }
        }
    }

    private func infoLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            let metrics = appStore.metrics(
                sessions: sessions,
                appointments: appointments,
                violations: violations
            )
            let activeTag = appStore.activeTag(from: tags)

            ZStack {
                StudioBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        StudioCard(emphasis: true) {
                            VStack(alignment: .leading, spacing: 16) {
                                StudioSectionLabel(title: "Invocation")
                                Text("进入专注模式")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(StudioTheme.textPrimary)
                                Text("弹层也使用和会话页一致的表面语言，只保留链条状态、当前标签和会话草稿。")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(StudioTheme.textSecondary)
                                HStack(spacing: 10) {
                                    StudioCapsuleLabel(title: "主链 \(metrics.mainChainLength)")
                                    StudioCapsuleLabel(title: "预约链 \(metrics.appointmentChainLength)")
                                    StudioCapsuleLabel(title: activeTag?.name ?? "未绑定标签", tone: .accent)
                                }
                            }
                        }

                        StudioCard {
                            SessionDraftForm(
                                draft: $draft,
                                policy: appStore.activeShieldPolicy(from: policies)
                            )
                        }

                        HStack(spacing: 14) {
                            StudioActionButton(
                                title: "开始专注",
                                subtitle: "立即写入运行态",
                                tone: .primary,
                                action: startSession
                            )

                            StudioActionButton(
                                title: "15 分钟后开始",
                                subtitle: "保留预约窗口",
                                tone: .secondary,
                                action: scheduleAppointment
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("进入专注模式")
            .navigationBarTitleDisplayMode(.inline)
            .studioNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationBackground(.clear)
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
            StudioBackground()

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
        .studioNavigationBar()
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
            StudioSectionLabel(title: activeSession == nil ? "Focus Session" : "Session In Motion")

            Text(activeSession?.goal ?? "把时长拨准，再安静地开始。")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(activeSession == nil ? "新的时间轮负责主节奏，下面只保留真正影响专注质量的设置。" : "当前会话正在运行。完成、标记不合格或主动退出，都在这里处理。")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var draftStudio: some View {
        VStack(spacing: 18) {
            StudioCard {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        StudioSectionLabel(title: "Duration")

                        Text("\(draft.durationMinutes) 分钟")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .monospacedDigit()
                    }

                    TimerWheelPicker(
                        selection: $draft.durationMinutes,
                        range: 5...180,
                        step: 1,
                        style: StudioTheme.wheelStyle
                    )
                    .frame(maxWidth: .infinity)

                    Text("\(draft.durationMinutes) min")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.1), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
            }

            StudioCard {
                VStack(alignment: .leading, spacing: 16) {
                    StudioSectionLabel(title: "目标")

                    TextField("这段专注要产出什么？", text: $draft.goal)
                        .textInputAutocapitalization(.never)
                        .studioTextEntry()

                    shieldComposer
                }
            }

            HStack(spacing: 14) {
                StudioActionButton(
                    title: "立即开始",
                    subtitle: "主链会话",
                    tone: .primary,
                    action: startQuickSession
                )

                StudioActionButton(
                    title: "预约 15 分钟后",
                    subtitle: "保留开始窗口",
                    tone: .secondary,
                    action: scheduleAppointment
                )
            }
        }
    }

    private var shieldComposer: some View {
        StudioInsetPanel {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    StudioSectionLabel(title: "Focus Shield")
                    Text(draft.shieldEnabled ? "会话启动时应用系统屏蔽" : "这次会话不应用系统屏蔽")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $draft.shieldEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(StudioTheme.accent)
            }

            if draft.shieldEnabled {
                if let activeShieldPolicy, activeShieldPolicy.selectedApps.isEmpty == false {
                    SessionChipRow(values: Array(activeShieldPolicy.selectedApps.prefix(4)))
                    Text(activeShieldPolicy.selectedApps.count > 4 ? "已选 \(activeShieldPolicy.selectedApps.count) 项，完整列表在设置页维护。" : "已连接设置页中的真实屏蔽策略。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textTertiary)
                } else {
                    Text("还没有可用的屏蔽目标。请先去设置页选择要拦截的 App 与网站。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textTertiary)
                }
            }
        }
    }

    private func runningStudio(_ activeSession: FocusSession) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(activeSession.startAt)))
                    let remaining = max(0, activeSession.durationSec - Int(context.date.timeIntervalSince(activeSession.startAt)))
                    let progress = activeSession.durationSec == 0 ? 0 : Double(remaining) / Double(activeSession.durationSec)
                    let endAt = activeSession.startAt.addingTimeInterval(TimeInterval(activeSession.durationSec))

                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            StudioCapsuleLabel(title: activeSession.source.label)
                            StudioCapsuleLabel(title: activeSession.tagName)
                            if activeSession.shieldEnabled {
                                StudioCapsuleLabel(title: "Shield On", tone: .accent)
                            }
                            Spacer()
                            StudioCapsuleLabel(title: "\(elapsed / 60) / \(activeSession.durationSec / 60) min")
                        }

                        StudioCountdownRing(
                            progress: progress,
                            remainingText: remaining.clockString,
                            detail: "开始于 \(activeSession.startAt.formatted(date: .omitted, time: .shortened)) · 预计结束 \(endAt.formatted(date: .omitted, time: .shortened))"
                        )

                        StudioInsetPanel {
                            sessionRuntimeLine(title: "当前目标", value: activeSession.goal)
                            sessionRuntimeLine(title: "会话时长", value: "\(activeSession.durationSec / 60) 分钟")
                            sessionRuntimeLine(title: "来源", value: activeSession.source.label)
                        }
                    }
                }

                if activeSession.shieldEnabled {
                    shieldRuntimePanel(activeSession)
                }

                VStack(spacing: 12) {
                    StudioActionButton(
                        title: "完成会话",
                        subtitle: "提交主链节点",
                        tone: .primary
                    ) {
                        try? appStore.completeSession(
                            activeSession,
                            sessions: sessions,
                            nodes: nodes,
                            context: modelContext
                        )
                    }

                    HStack(spacing: 12) {
                        StudioActionButton(
                            title: "标记不合格",
                            subtitle: "记录质量失败",
                            tone: .secondary
                        ) {
                            try? appStore.recordQualityFailure(activeSession, context: modelContext)
                        }

                        StudioActionButton(
                            title: "退出",
                            subtitle: "终止当前会话",
                            tone: .danger
                        ) {
                            try? appStore.abandonSession(activeSession, context: modelContext)
                        }
                    }
                }
            }
        }
    }

    private func sessionRuntimeLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func shieldRuntimePanel(_ activeSession: FocusSession) -> some View {
        StudioInsetPanel {
            StudioSectionLabel(title: "Shield Runtime")

            Text(activeShieldPolicy?.selectedApps.joined(separator: " · ") ?? "未配置屏蔽目标")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
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
    }

    private func appointmentStudio(_ appointment: Appointment) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StudioSectionLabel(title: "当前预约链")
                    Spacer()
                    StudioCapsuleLabel(title: "Window")
                }

                Text(appointment.goal)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)

                Text("开始于 \(appointment.scheduledStartAt.formatted(date: .omitted, time: .shortened))，窗口截止 \(appointment.windowEndAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)

                StudioActionButton(
                    title: "履约并开始",
                    subtitle: "接入主链",
                    tone: .secondary
                ) {
                    fulfillAppointment(appointment)
                }
            }
        }
    }

    private var recentSessionsStudio: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StudioSectionLabel(title: "最近会话")
                    Spacer()
                    Text("\(sessions.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .monospacedDigit()
                }

                if sessions.isEmpty {
                    StudioEmptyState(
                        title: "还没有会话记录",
                        message: "开始第一段高质量专注，历史才有意义。"
                    )
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

private struct SessionChipRow: View {
    let values: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(values, id: \.self) { value in
                    StudioCapsuleLabel(title: value)
                }
            }
        }
    }
}

private struct ChainsView: View {
    let sessions: [FocusSession]
    let appointments: [Appointment]
    let nodes: [ChainNode]

    private var mainNodes: [ChainNode] {
        nodes.filter { $0.chainType == .main }
    }

    private var appointmentNodes: [ChainNode] {
        nodes.filter { $0.chainType == .appointment }
    }

    private var failedSessions: [FocusSession] {
        sessions.filter { $0.status == .failed }
    }

    private var missedAppointments: [Appointment] {
        appointments.filter { $0.status == .missed }
    }

    var body: some View {
        ZStack {
            StudioBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    StudioCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            StudioSectionLabel(title: "Chains")
                            Text("链条只展示连续性与断裂点。主链、预约链、失败记录各自独立，避免列表式噪音。")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.textSecondary)
                            HStack(spacing: 10) {
                                StudioCapsuleLabel(title: "主链 \(mainNodes.count)")
                                StudioCapsuleLabel(title: "预约 \(appointmentNodes.count)")
                                StudioCapsuleLabel(
                                    title: "失败 \(failedSessions.count + missedAppointments.count)",
                                    tone: failedSessions.isEmpty && missedAppointments.isEmpty ? .neutral : .danger
                                )
                            }
                        }
                    }

                    chainSectionCard(
                        title: "主链节点",
                        subtitle: "已完成的主链提交节点",
                        nodes: mainNodes,
                        emptyTitle: "暂无主链节点",
                        emptyMessage: "完成一次会话后，这里才会出现真正有意义的证明链。"
                    )

                    chainSectionCard(
                        title: "预约链节点",
                        subtitle: "预约履约产生的链条记录",
                        nodes: appointmentNodes,
                        emptyTitle: "暂无预约链节点",
                        emptyMessage: "先从一条最小预约开始，让它稳定接入主链。"
                    )

                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                StudioSectionLabel(title: "Failures")
                                Spacer()
                                StudioCapsuleLabel(
                                    title: "\(failedSessions.count + missedAppointments.count)",
                                    tone: failedSessions.isEmpty && missedAppointments.isEmpty ? .neutral : .danger
                                )
                            }

                            if failedSessions.isEmpty && missedAppointments.isEmpty {
                                StudioEmptyState(
                                    title: "还没有断链事件",
                                    message: "先保持完成率，让失败记录保持为空。"
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(failedSessions, id: \.id) { session in
                                        ChainFailureRow(
                                            title: session.goal,
                                            detail: session.failedReason ?? "未知失败",
                                            timestamp: session.startAt
                                        )
                                    }
                                    ForEach(missedAppointments, id: \.id) { appointment in
                                        ChainFailureRow(
                                            title: appointment.goal,
                                            detail: "预约未履约",
                                            timestamp: appointment.scheduledStartAt
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("链条")
        .navigationBarTitleDisplayMode(.inline)
        .studioNavigationBar()
    }

    private func chainSectionCard(
        title: String,
        subtitle: String,
        nodes: [ChainNode],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        StudioSectionLabel(title: title)
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    Spacer()
                    StudioCapsuleLabel(title: "\(nodes.count)")
                }

                if nodes.isEmpty {
                    StudioEmptyState(title: emptyTitle, message: emptyMessage)
                } else {
                    VStack(spacing: 12) {
                        ForEach(nodes, id: \.id) { node in
                            ChainNodeRow(node: node)
                        }
                    }
                }
            }
        }
    }
}

private struct PrecedentsView: View {
    let violations: [ViolationEvent]
    let rules: [PrecedentRule]

    private var pendingViolations: [ViolationEvent] {
        violations.filter { $0.decisionStatus == .pending }
    }

    var body: some View {
        ZStack {
            StudioBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    StudioCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            StudioSectionLabel(title: "Precedents")
                            Text("判例页负责展示违规事实与已生效规则。优先把待裁决状态和已有规则边界说清楚。")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.textSecondary)
                            HStack(spacing: 10) {
                                StudioCapsuleLabel(
                                    title: "待裁决 \(pendingViolations.count)",
                                    tone: pendingViolations.isEmpty ? .neutral : .danger
                                )
                                StudioCapsuleLabel(title: "规则 \(rules.count)")
                            }
                        }
                    }

                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                StudioSectionLabel(title: "违规事件")
                                Spacer()
                                StudioCapsuleLabel(title: "\(violations.count)")
                            }

                            if violations.isEmpty {
                                StudioEmptyState(
                                    title: "暂无违规事件",
                                    message: "保持会话完成质量，这里就应该尽量为空。"
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(violations, id: \.id) { event in
                                        ViolationEventRow(event: event)
                                    }
                                }
                            }
                        }
                    }

                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                StudioSectionLabel(title: "生效规则")
                                Spacer()
                                StudioCapsuleLabel(title: "\(rules.count)")
                            }

                            if rules.isEmpty {
                                StudioEmptyState(
                                    title: "暂无判例规则",
                                    message: "只有在做出裁决后，这里才会形成真正的规则边界。"
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(rules, id: \.id) { rule in
                                        PrecedentRuleRow(rule: rule)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("判例")
        .navigationBarTitleDisplayMode(.inline)
        .studioNavigationBar()
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

    private var activeTag: Tag? {
        appStore.activeTag(from: tags)
    }

    private var activeConfiguration: AppConfiguration? {
        appStore.activeConfiguration(from: configurations)
    }

    private var activePolicy: ShieldPolicy? {
        appStore.activeShieldPolicy(from: policies)
    }

    var body: some View {
        ZStack {
            StudioBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    tagManagementCard

                    if let activeConfiguration {
                        nfcWriteCard(configuration: activeConfiguration)
                        appClipDebugCard(configuration: activeConfiguration)
                    }

                    if let activePolicy {
                        FocusShieldSection(policy: activePolicy)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .studioNavigationBar()
    }

    private var tagManagementCard: some View {
        StudioCard(emphasis: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        StudioSectionLabel(title: "Tags")
                        Text("维护当前专注摆件和标签入口，确保真实触碰始终命中一张有效标签。")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    Spacer()
                    StudioCapsuleLabel(title: "\(tags.count)")
                }

                if tags.isEmpty {
                    StudioEmptyState(
                        title: "还没有标签",
                        message: "先创建一张标签，再把它写入 NFC。"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(tags, id: \.id) { tag in
                            HStack(alignment: .center, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tag.name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(StudioTheme.textPrimary)
                                    Text(tag.tagPublicId)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(StudioTheme.textTertiary)
                                }

                                Spacer()

                                if tag.status == .active {
                                    StudioCapsuleLabel(title: "当前", tone: .accent)
                                } else {
                                    Button("设为当前") {
                                        try? appStore.activateTag(tag, tags: tags, context: modelContext)
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                            .padding(16)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    TextField("新增标签名称", text: $newTagName)
                        .textInputAutocapitalization(.never)
                        .studioTextEntry()

                    StudioActionButton(
                        title: "添加标签",
                        subtitle: "创建新的 NFC 绑定目标",
                        tone: .secondary
                    ) {
                        try? appStore.addTag(name: newTagName, context: modelContext)
                        newTagName = ""
                    }
                }
            }
        }
    }

    private func nfcWriteCard(configuration: AppConfiguration) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                StudioSectionLabel(title: "NFC 写码")

                TextField("Invocation Host", text: Binding(
                    get: { configuration.invocationHost },
                    set: { try? appStore.updateInvocationHost(configuration, host: $0, context: modelContext) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .studioTextEntry()

                if let activeTag,
                   let url = appStore.invocationURL(for: activeTag, configuration: configuration) {
                    settingsInfoBlock(title: "当前写入 URL", value: url.absoluteString)
                }

                HStack(spacing: 14) {
                    StudioActionButton(
                        title: "写入当前标签",
                        subtitle: "把 Invocation URL 写进 NFC",
                        tone: .primary,
                        action: writeCurrentTag
                    )

                    StudioActionButton(
                        title: "读取标签内容",
                        subtitle: "检查 UID 与原始记录",
                        tone: .secondary,
                        action: readCurrentTag
                    )
                }

                settingsInfoBlock(title: "NFC 状态", value: nfcManager.statusMessage)
            }
        }
    }

    private func appClipDebugCard(configuration: AppConfiguration) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                StudioSectionLabel(title: "App Clip 调试")

                if let experienceURL = appStore.appClipExperienceURL(for: configuration) {
                    settingsInfoBlock(title: "Connect Experience URL", value: experienceURL.absoluteString)
                }

                if let activeTag,
                   let url = appStore.invocationURL(for: activeTag, configuration: configuration) {
                    settingsInfoBlock(title: "Invocation URL", value: url.absoluteString)
                    settingsInfoBlock(
                        title: "AASA",
                        value: "https://\(configuration.invocationHost)/.well-known/apple-app-site-association"
                    )
                }

                StudioInsetPanel {
                    Text("真机调试要点")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                    Text("1. App Store Connect 中的 App Clip Experience URL 使用短地址 https://\(configuration.invocationHost)；物理 NFC 标签写入当前显示的 Invocation URL。")
                    Text("2. 每张 NFC 标签可以各自写入不同的 /i/<tagId>，不需要在 Connect 里逐条注册。")
                    Text("3. 若设备已安装完整 App，点卡片的“打开”后 invocation 会交给完整 App 继续。")
                    Text("4. 如果你之前在 设置 > Developer > Local Experiences 注册过本地体验，测线上链路前先删除它。")
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
            }
        }
    }

    private func settingsInfoBlock(title: String, value: String) -> some View {
        StudioInsetPanel {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FocusShieldSection: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var focusShieldController: FocusShieldController

    let policy: ShieldPolicy

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                StudioSectionLabel(title: "Focus Shield")

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("启用专注期屏蔽")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.textPrimary)
                        Text("只在 Focus Shield 打开且会话处于运行中时应用系统级屏蔽。")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: shieldEnabledBinding)
                        .labelsHidden()
                        .tint(StudioTheme.accent)
                }

                StudioActionButton(
                    title: "选择屏蔽 App 与网站",
                    subtitle: "打开系统选择器",
                    tone: .secondary
                ) {
                    Task {
                        _ = await focusShieldController.beginSelectionFlow()
                    }
                }

                selectedSummaryRow
                tokenSection("已选 App", tokens: focusShieldController.selectedApplicationTokens)
                tokenSection("已选分类", tokens: focusShieldController.selectedCategoryTokens)
                tokenSection("已选网站", tokens: focusShieldController.selectedWebDomainTokens)

                Text(statusCopy)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastErrorMessage = focusShieldController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                }
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
            StudioInsetPanel {
                Text("已选项目")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
                Text(summaryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            StudioEmptyState(
                title: "尚未选择任何 App、分类或网站",
                message: "启用 Focus Shield 后，先补齐真实的屏蔽目标。"
            )
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            StudioTokenChip {
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.white)
                            }
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            StudioTokenChip {
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.white)
                            }
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tokens, id: \.self) { token in
                            StudioTokenChip {
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.white)
                            }
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
            ZStack {
                StudioBackground()

                VStack(spacing: 22) {
                    StudioCard(emphasis: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            StudioSectionLabel(title: "Decision")
                            Text(event.type.label)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.textPrimary)
                            Text(event.payload)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("每次违规必须二选一：断链重置，或者永久允许同类行为。")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.textTertiary)
                        }
                    }

                    StudioActionButton(
                        title: "断链重置",
                        subtitle: "把这次行为视为必须修正",
                        tone: .primary
                    ) {
                        apply(.reset)
                    }

                    StudioActionButton(
                        title: "永久允许该类行为",
                        subtitle: "从此不再因此触发断链",
                        tone: .secondary
                    ) {
                        apply(.allowForever)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .navigationTitle("下必为例")
            .navigationBarTitleDisplayMode(.inline)
            .studioNavigationBar()
        }
        .presentationBackground(.clear)
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
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionLabel(title: "会话配置")

            TextField("目标", text: $draft.goal)
                .textInputAutocapitalization(.never)
                .studioTextEntry()

            StudioInsetPanel {
                HStack {
                    Text("时长")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                    Spacer()
                    Text("\(draft.durationMinutes) 分钟")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .monospacedDigit()
                }

                Stepper("", value: $draft.durationMinutes, in: 5...180, step: 1)
                    .labelsHidden()
                    .tint(StudioTheme.accent)
            }

            StudioInsetPanel {
                HStack {
                    Text("启用 Focus Shield")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $draft.shieldEnabled)
                        .labelsHidden()
                        .tint(StudioTheme.accent)
                }

                if draft.shieldEnabled {
                    Text(policy?.selectedApps.joined(separator: "、") ?? "请先在设置页配置屏蔽 App")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        StudioMetricTile(title: title, value: value, subtitle: subtitle)
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
                Text(session.status.displayLabel)
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
            StudioTheme.accent
        case .failed:
            Color(red: 0.93, green: 0.43, blue: 0.43)
        case .running:
            StudioTheme.cool
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(node.chainType.label) #\(node.nodeIndex)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
                Text(node.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
            }
            Text(node.summary)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(node.proofHash.prefix(18)) + "...")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.textTertiary)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ChainFailureRow: View {
    let title: String
    let detail: String
    let timestamp: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
                StudioCapsuleLabel(title: timestamp.formatted(date: .abbreviated, time: .shortened))
            }
            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ViolationEventRow: View {
    let event: ViolationEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(event.type.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
                StudioCapsuleLabel(title: event.decisionStatus.displayLabel, tone: event.decisionStatus.capsuleTone)
            }

            Text(event.payload)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(event.type.suggestion)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if event.note.isEmpty == false {
                Text(event.note)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PrecedentRuleRow: View {
    let rule: PrecedentRule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(rule.violationType.label) · \(rule.decision.label)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                Spacer()
                StudioCapsuleLabel(title: rule.createdAt.formatted(date: .abbreviated, time: .omitted))
            }

            if rule.note.isEmpty == false {
                Text(rule.note)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)
            }

            if rule.scope.isEmpty == false {
                Text(rule.scope)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private extension FocusSessionStatus {
    var displayLabel: String {
        switch self {
        case .ready:
            "就绪"
        case .running:
            "进行中"
        case .completed:
            "已完成"
        case .failed:
            "失败"
        }
    }
}

private extension ViolationDecisionStatus {
    var displayLabel: String {
        switch self {
        case .pending:
            "待裁决"
        case .reset:
            "已重置"
        case .allowed:
            "已允许"
        }
    }

    var capsuleTone: StudioCapsuleTone {
        switch self {
        case .pending:
            .danger
        case .reset:
            .neutral
        case .allowed:
            .accent
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
