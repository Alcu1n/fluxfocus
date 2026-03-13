//
//  ContentView.swift
//  fluxfocus
//
//  Created by Codex on 2026/3/12.
//

import SwiftData
import SwiftUI

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
        guard let publicId = appStore.parseInvocationURL(url),
              let tag = appStore.tag(for: publicId, tags: tags) else {
            nfcAlert = NFCAlert(
                title: "标签无效",
                message: "读取到了 NFC 内容，但不是当前 App 可识别的 FluxFocus invocation URL。"
            )
            return
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

        let shouldAutoStart = true
        if shouldAutoStart {
            try? appStore.startSession(
                draft: quickStartDraft,
                tag: tag,
                sessions: sessions,
                nodes: nodes,
                context: modelContext,
                source: .nfcInvocation
            )
            selectedTab = .session
        } else {
            showInvocationSheet = true
        }
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
            Text("当前 MVP 以本地规则引擎运行。这里模拟 NFC / App Clip 入口，并保留主链、预约链、判例与屏蔽策略。")
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
                Label("真实触碰 NFC 并打开入口 Sheet", systemImage: "iphone.gen3.radiowaves.left.and.right")
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
        let activeSession = appStore.runningSession(from: sessions)
        let appointment = appStore.scheduledAppointment(from: appointments)
        let shieldPolicy = appStore.activeShieldPolicy(from: policies)

        List {
            if let activeSession {
                runningCard(activeSession: activeSession, shieldPolicy: shieldPolicy)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else {
                Section("快速开始") {
                    SessionDraftForm(draft: $draft, policy: shieldPolicy)
                    Button("立即开始主链") {
                        startQuickSession()
                    }
                    Button("预约 15 分钟后开始") {
                        scheduleAppointment()
                    }
                }
            }

            if let appointment {
                Section("当前预约链") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appointment.goal)
                            .font(.headline)
                        Text("开始于 \(appointment.scheduledStartAt.formatted(date: .omitted, time: .shortened))，窗口截止 \(appointment.windowEndAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("履约并开始主链") {
                            fulfillAppointment(appointment)
                        }
                    }
                }
            }

            Section("最近会话") {
                if sessions.isEmpty {
                    Text("还没有会话记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions.prefix(8), id: \.id) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
        .navigationTitle("会话")
    }

    private func runningCard(activeSession: FocusSession, shieldPolicy: ShieldPolicy?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, activeSession.durationSec - Int(context.date.timeIntervalSince(activeSession.startAt)))
                VStack(alignment: .leading, spacing: 8) {
                    Text(activeSession.goal)
                        .font(.title3.bold())
                    Text(remaining.clockString)
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(activeSession.source.label) · \(activeSession.tagName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if activeSession.shieldEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Focus Shield")
                        .font(.headline)
                    Text(shieldPolicy?.selectedApps.joined(separator: "、") ?? "未配置屏蔽 App")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(shieldPolicy?.selectedApps ?? [], id: \.self) { app in
                                Button(app) {
                                    try? appStore.simulateBlockedAppAttempt(
                                        appName: app,
                                        session: activeSession,
                                        context: modelContext
                                    )
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("完成会话") {
                    try? appStore.completeSession(
                        activeSession,
                        sessions: sessions,
                        nodes: nodes,
                        context: modelContext
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("标记不合格") {
                    try? appStore.recordQualityFailure(activeSession, context: modelContext)
                }
                .buttonStyle(.bordered)

                Button("退出") {
                    try? appStore.abandonSession(activeSession, context: modelContext)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                        Text("1. 测试 App Clip 卡片时，测试机上不要安装完整 App。")
                        Text("2. NFC 标签必须写入当前显示的 invocation URL，而不是普通文本。")
                        Text("3. App Store Connect 中的 App Clip Experience 需要使用 host \(configuration.invocationHost) 和路径前缀 /i/。")
                        Text("4. 如果你之前在 设置 > Developer > Local Experiences 注册过本地 App Clip 调试项，先删除它，否则系统会优先走本地体验。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let policy = appStore.activeShieldPolicy(from: policies) {
                Section("Focus Shield") {
                    Toggle("启用专注期屏蔽", isOn: Binding(
                        get: { policy.enabled },
                        set: { try? appStore.updateShieldEnabled(policy: policy, enabled: $0, context: modelContext) }
                    ))

                    ForEach(appStore.shieldCatalog, id: \.self) { app in
                        Toggle(app, isOn: Binding(
                            get: { policy.selectedApps.contains(app) },
                            set: { try? appStore.updateShieldSelection(policy: policy, app: app, isSelected: $0, context: modelContext) }
                        ))
                    }
                }
            }
        }
        .navigationTitle("设置")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.goal)
                Spacer()
                Text(session.status.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(session.status == .completed ? .green : session.status == .failed ? .red : .secondary)
            }
            Text("\(session.source.label) · \(session.durationSec.clockString)")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
