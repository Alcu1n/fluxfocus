// [IN]: Foundation, CryptoKit, SwiftData, app models, and NFC/App Clip URL rules / Foundation、CryptoKit、SwiftData、应用模型与 NFC/App Clip URL 规则
// [OUT]: AppStore state orchestration, short invocation URL generation, NFC-driven session mutations, precedent handling, legacy-violation cleanup, and derived home-chain/tag snapshots / AppStore 状态编排、短 invocation URL 生成、NFC 驱动的会话变更、判例处理、遗留违规清理与派生首页/标签快照
// [POS]: Main domain service for local MVP state, invocation routing, NFC-governed lifecycle, and dashboard derivation / 本地 MVP 状态、invocation 路由、NFC 治理生命周期与看板派生的主领域服务
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import CryptoKit
import Foundation
import Observation
import SwiftData

struct InvocationRoute: Equatable {
    let publicId: String
    let clipCompleted: Bool
    let clipDurationMinutes: Int?
}

enum SessionTagTouchDisposition: Equatable {
    case enterSession
    case rejectMismatchedTag(expectedTagName: String)
    case triggerManualExit
    case completeAwaitingSession
}

struct SessionLifecyclePlan: Equatable {
    let targetStatus: FocusSessionStatus
    let closesSession: Bool
    let nextMainChainNodeIndex: Int?
}

struct ManualExitReasonResolution: Equatable {
    let key: String
    let text: String
    let reusesExistingRule: Bool
}

@MainActor
@Observable
final class AppStore {
    let shieldCatalog = [
        "抖音",
        "小红书",
        "微博",
        "Bilibili",
        "YouTube",
        "微信",
        "Slack",
        "Safari"
    ]

    private(set) var didBootstrap = false
    private let invocationPathPrefix = "i"
    private let fullAppHandoffScheme = "fluxfocus"
    private let fullAppHandoffHost = "focus"

    func bootstrapIfNeeded(context: ModelContext) throws {
        guard !didBootstrap else { return }

        let tagFetch = FetchDescriptor<Tag>()
        let existingTags = try context.fetch(tagFetch)
        if existingTags.isEmpty {
            context.insert(
                Tag(
                    tagPublicId: "desk-altar-001",
                    uidHash: "ntag216-demo",
                    name: "书桌摆件",
                    status: .active
                )
            )
        }

        let shieldFetch = FetchDescriptor<ShieldPolicy>()
        let policies = try context.fetch(shieldFetch)
        if policies.isEmpty {
            context.insert(
                ShieldPolicy(
                    selectedApps: ["抖音", "小红书", "微博", "YouTube"],
                    enabled: true
                )
            )
        }

        let configFetch = FetchDescriptor<AppConfiguration>()
        let configs = try context.fetch(configFetch)
        if configs.isEmpty {
            context.insert(
                AppConfiguration(
                    invocationHost: "fluxfocusclip.lraitech.com",
                    signatureSalt: "legacy-unused"
                )
            )
        }

        try purgeDeprecatedViolationArtifacts(context: context)
        try expireOverdueAppointments(context: context, now: .now)
        try context.save()
        didBootstrap = true
    }

    func activeTag(from tags: [Tag]) -> Tag? {
        tags.first(where: { $0.status == .active }) ?? tags.first
    }

    func activeShieldPolicy(from policies: [ShieldPolicy]) -> ShieldPolicy? {
        policies.first
    }

    func activeConfiguration(from configurations: [AppConfiguration]) -> AppConfiguration? {
        configurations.first
    }

    func appClipExperienceURL(for configuration: AppConfiguration) -> URL? {
        baseURL(for: configuration)
    }

    func invocationURL(for tag: Tag, configuration: AppConfiguration) -> URL? {
        guard var components = baseComponents(for: configuration) else { return nil }
        components.path = invocationPath(for: tag.tagPublicId)
        return components.url
    }

    func parseInvocationURL(_ url: URL) -> String? {
        parseInvocationRoute(url)?.publicId
    }

    func parseInvocationRoute(_ url: URL) -> InvocationRoute? {
        if url.scheme?.lowercased() == fullAppHandoffScheme {
            return parseFullAppHandoffRoute(url)
        }
        return parseWebInvocationRoute(url)
    }

    func invocationPath(for publicId: String) -> String {
        "/\(invocationPathPrefix)/\(publicId)"
    }

    func fullAppLaunchURL(from url: URL) -> URL? {
        guard let route = parseInvocationRoute(url) else { return nil }

        var components = URLComponents()
        components.scheme = fullAppHandoffScheme
        components.host = fullAppHandoffHost
        components.path = "/\(route.publicId)"

        var queryItems: [URLQueryItem] = []
        if route.clipCompleted {
            queryItems.append(URLQueryItem(name: "clip_completed", value: "1"))
        }
        if let clipDurationMinutes = route.clipDurationMinutes {
            queryItems.append(URLQueryItem(name: "clip_duration", value: "\(clipDurationMinutes)"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    func tag(for publicId: String, tags: [Tag]) -> Tag? {
        tags.first(where: { $0.tagPublicId == publicId })
    }

    func bindPhysicalTag(
        _ tag: Tag,
        uidHex: String,
        context: ModelContext
    ) throws {
        tag.uidHash = uidHex
        try context.save()
    }

    func updateInvocationHost(
        _ configuration: AppConfiguration,
        host: String,
        context: ModelContext
    ) throws {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        configuration.invocationHost = clean
        configuration.updatedAt = .now
        try context.save()
    }

    func runningSession(from sessions: [FocusSession]) -> FocusSession? {
        sessions.first(where: { $0.status == .running })
    }

    func activeSession(from sessions: [FocusSession]) -> FocusSession? {
        sessions.first(where: { $0.status.isActive })
    }

    func sessionTagTouchDisposition(
        for tag: Tag,
        sessions: [FocusSession]
    ) -> SessionTagTouchDisposition {
        let activeSession = activeSession(from: sessions)
        return FocusDomainLogic.sessionTagTouchDisposition(
            SessionTouchContext(
                scannedTagPublicId: tag.tagPublicId,
                activeSessionTagPublicId: activeSession?.tagPublicId,
                activeSessionTagName: activeSession?.tagName,
                activeSessionStatus: activeSession?.status
            )
        )
    }

    func lifecyclePlan(
        for status: FocusSessionStatus,
        currentMainChainCount: Int
    ) -> SessionLifecyclePlan? {
        FocusDomainLogic.lifecyclePlan(
            for: status,
            currentMainChainCount: currentMainChainCount
        )
    }

    func manualExitReasonResolution(
        _ rawReason: String?,
        existingRules: [PrecedentRule]
    ) -> ManualExitReasonResolution? {
        FocusDomainLogic.manualExitReasonResolution(
            rawReason,
            existingRules: existingRules
                .filter { $0.violationType == .manualExit && $0.decision == .allowForever }
                .map {
                    ManualExitRuleDigest(
                        reasonKey: $0.reasonKey,
                        reasonText: $0.reasonText
                    )
                }
        )
    }

    func scheduledAppointment(from appointments: [Appointment]) -> Appointment? {
        appointments.sorted { $0.scheduledStartAt < $1.scheduledStartAt }
            .first(where: { $0.status == .scheduled })
    }

    func metrics(
        sessions: [FocusSession],
        appointments: [Appointment],
        violations: [ViolationEvent]
    ) -> DashboardMetrics {
        let calendar = Calendar.current
        let today = Date.now
        let todaySessions = sessions.filter {
            $0.status == .completed &&
            calendar.isDate($0.startAt, inSameDayAs: today)
        }
        let weekSessions = sessions.filter {
            $0.status == .completed &&
            calendar.isDate($0.startAt, equalTo: today, toGranularity: .weekOfYear)
        }
        let mainChain = chainLengthForSessions(sessions)
        let appointmentChain = chainLengthForAppointments(appointments)
        let shieldBlocks = violations.filter { $0.type == .blockedAppAttempt }.count
        let breaks = sessions.filter { $0.status == .failed }.count

        return DashboardMetrics(
            focusSecondsToday: todaySessions.reduce(0) { $0 + $1.durationSec },
            completedThisWeek: weekSessions.count,
            mainChainLength: mainChain,
            appointmentChainLength: appointmentChain,
            breakCount: breaks,
            shieldBlocks: shieldBlocks
        )
    }

    func homeChainSnapshot(
        sessions: [FocusSession],
        nodes: [ChainNode],
        pulseSpan: Int = 12,
        visibleNodeCount: Int = 6
    ) -> HomeChainSnapshot {
        let calendar = Calendar.current
        let today = Date.now
        let completedSessions = sessions.filter { $0.status == .completed }
        let sortedCompletedSessions = completedSessions.sorted { $0.startAt < $1.startAt }
        let currentChainSessions = currentChainSessions(from: sessions)
        let currentChainNodeMap = Dictionary(
            uniqueKeysWithValues: nodes
                .filter { $0.chainType == .main }
                .map { ($0.relatedEntityId, $0) }
        )
        let recentNodes = Array(currentChainSessions.enumerated().suffix(visibleNodeCount)).map { offset, session in
            let mappedNode = currentChainNodeMap[session.id.uuidString]
            let fallbackIndex = offset + 1
            return HomeChainVisualNode(
                id: session.id,
                chainIndex: mappedNode?.nodeIndex ?? fallbackIndex,
                title: shortChainTitle(from: session.goal),
                durationSec: session.durationSec,
                completedAt: session.endAt ?? session.startAt,
                proofSnippet: String((mappedNode?.proofHash ?? session.id.uuidString.lowercased()).prefix(6))
            )
        }

        let completedByDay = Dictionary(grouping: completedSessions) {
            calendar.startOfDay(for: $0.startAt)
        }
        let currentChainDays = Set(currentChainSessions.map { calendar.startOfDay(for: $0.startAt) })
        let startOfToday = calendar.startOfDay(for: today)
        let dailyPulses = (0..<pulseSpan).compactMap { offset -> HomeChainDailyPulse? in
            guard let day = calendar.date(byAdding: .day, value: offset - (pulseSpan - 1), to: startOfToday) else {
                return nil
            }

            let daySessions = completedByDay[day] ?? []
            return HomeChainDailyPulse(
                dayStart: day,
                totalFocusSeconds: daySessions.reduce(0) { $0 + $1.durationSec },
                completedCount: daySessions.count,
                contributesToCurrentChain: currentChainDays.contains(day)
            )
        }

        return HomeChainSnapshot(
            currentLength: currentChainSessions.count,
            archivedLength: max(currentChainSessions.count - recentNodes.count, 0),
            totalCompletedSessions: completedSessions.count,
            totalFocusSeconds: completedSessions.reduce(0) { $0 + $1.durationSec },
            focusSecondsToday: completedSessions
                .filter { calendar.isDate($0.startAt, inSameDayAs: today) }
                .reduce(0) { $0 + $1.durationSec },
            todayContributionCount: currentChainSessions.filter {
                calendar.isDate($0.startAt, inSameDayAs: today)
            }.count,
            shieldedSessionCount: completedSessions.filter(\.shieldEnabled).count,
            latestSummary: currentChainSessions.last?.goal ?? sortedCompletedSessions.last?.goal ?? "下一节链条等待被点亮",
            latestCompletionAt: currentChainSessions.last?.endAt ?? currentChainSessions.last?.startAt,
            recentNodes: recentNodes,
            dailyPulses: dailyPulses
        )
    }

    func startSession(
        draft: SessionDraft,
        tag: Tag,
        sessions: [FocusSession],
        nodes: [ChainNode],
        context: ModelContext,
        source: SessionSource,
        appointment: Appointment? = nil
    ) throws {
        guard activeSession(from: sessions) == nil else { return }

        try expireOverdueAppointments(context: context, now: .now)

        let session = FocusSession(
            tagPublicId: tag.tagPublicId,
            tagName: tag.name,
            goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名专注" : draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSec: max(5, draft.durationMinutes) * 60,
            status: .running,
            source: source,
            shieldEnabled: draft.shieldEnabled
        )
        context.insert(session)

        if let appointment {
            let nextIndex = chainLengthForAppointments(fetchAppointments(context: context)) + 1
            appointment.status = .fulfilled
            appointment.fulfilledSessionId = session.id
            context.insert(
                ChainNode(
                    chainType: .appointment,
                    nodeIndex: nextIndex,
                    relatedEntityId: appointment.id.uuidString,
                    proofHash: proofHash(
                        previousHash: latestHash(in: nodes, chainType: .appointment),
                        components: [appointment.id.uuidString, appointment.goal, session.startAt.ISO8601Format()]
                    ),
                    summary: "预约已履约：\(appointment.goal)"
                )
            )
        }

        try context.save()
    }

    func markAwaitingNFCCompletion(
        _ session: FocusSession,
        context: ModelContext
    ) throws {
        guard let plan = lifecyclePlan(for: session.status, currentMainChainCount: 0),
              plan.targetStatus == .awaitingNFCCompletion else {
            return
        }

        session.status = plan.targetStatus
        try context.save()
    }

    func completeAwaitingSession(
        _ session: FocusSession,
        sessions: [FocusSession],
        nodes: [ChainNode],
        context: ModelContext
    ) throws {
        guard let plan = lifecyclePlan(
            for: session.status,
            currentMainChainCount: chainLengthForSessions(sessions)
        ),
        let nextIndex = plan.nextMainChainNodeIndex,
        plan.targetStatus == .completed
        else {
            return
        }

        session.status = plan.targetStatus
        if plan.closesSession {
            session.endAt = .now
        }

        context.insert(
            ChainNode(
                chainType: .main,
                nodeIndex: nextIndex,
                relatedEntityId: session.id.uuidString,
                proofHash: proofHash(
                    previousHash: latestHash(in: nodes, chainType: .main),
                    components: [session.id.uuidString, session.goal, "\(session.durationSec)"]
                ),
                summary: "完成：\(session.goal)"
            )
        )

        try context.save()
    }

    func scheduleAppointment(
        draft: SessionDraft,
        tag: Tag,
        context: ModelContext
    ) throws {
        let scheduledStart = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let windowEnd = Calendar.current.date(byAdding: .minute, value: 10, to: scheduledStart) ?? scheduledStart
        context.insert(
            Appointment(
                tagPublicId: tag.tagPublicId,
                tagName: tag.name,
                goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "预约专注" : draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
                durationSec: max(5, draft.durationMinutes) * 60,
                scheduledStartAt: scheduledStart,
                windowEndAt: windowEnd
            )
        )
        try context.save()
    }

    func abandonSessionByNFC(
        _ session: FocusSession,
        context: ModelContext
    ) throws {
        try recordViolation(
            type: .manualExit,
            payload: "用户通过 NFC 主动退出当前会话",
            session: session,
            appointment: nil,
            context: context
        )
    }

    func recordQualityFailure(
        _ session: FocusSession,
        context: ModelContext
    ) throws {
        try recordViolation(
            type: .qualityFailure,
            payload: "用户手动标记本次状态不合格",
            session: session,
            appointment: nil,
            context: context
        )
    }

    func simulateBlockedAppAttempt(
        appName: String,
        session: FocusSession,
        context: ModelContext
    ) throws {
        try recordViolation(
            type: .blockedAppAttempt,
            payload: "尝试打开 \(appName)",
            session: session,
            appointment: nil,
            context: context
        )
    }

    func applyDecision(
        event: ViolationEvent,
        decision: PrecedentDecision,
        reasonText: String? = nil,
        sessions: [FocusSession],
        context: ModelContext
    ) throws {
        let resolution = manualExitReasonResolution(
            reasonText,
            existingRules: manualExitRules(context: context)
        )
        let cleanReasonText = resolution?.text ?? cleanedManualExitReason(reasonText)
        let cleanReasonKey = resolution?.key ?? normalizedManualExitReason(reasonText)

        if decision == .allowForever,
           event.type == .manualExit,
           cleanReasonKey.isEmpty {
            return
        }

        let rule: PrecedentRule

        if decision == .allowForever,
           event.type == .manualExit,
           cleanReasonKey.isEmpty == false,
           resolution?.reusesExistingRule == true,
           let existingRule = manualExitRule(reasonKey: cleanReasonKey, context: context) {
            rule = existingRule
        } else {
            let newRule = PrecedentRule(
                violationType: event.type,
                decision: decision,
                scope: event.type == .manualExit ? "manual-exit-v1" : "mvp-v1",
                reasonKey: event.type == .manualExit ? cleanReasonKey : "",
                reasonText: event.type == .manualExit ? cleanReasonText : "",
                note: decision == .allowForever ? "后续同类行为自动放行" : "本次违规触发断链"
            )
            context.insert(newRule)
            rule = newRule
        }

        let resolvedReasonKey = event.type == .manualExit ? rule.reasonKey : ""
        let resolvedReasonText = event.type == .manualExit ? rule.reasonText : ""

        event.decisionStatus = decision == .reset ? .reset : .allowed
        event.resolvedAt = .now
        event.resolvedRuleId = rule.id
        event.decisionReasonKey = resolvedReasonKey
        event.decisionReasonText = resolvedReasonText
        event.note =
            decision == .allowForever && resolvedReasonText.isEmpty == false
            ? "永久允许：\(resolvedReasonText)"
            : decision.label

        if decision == .reset,
           let sessionId = event.sessionId,
           let session = sessions.first(where: { $0.id == sessionId }) {
            session.status = .failed
            session.endAt = .now
            session.failedReason = event.type.label
        }

        if decision == .allowForever,
           event.type == .manualExit,
           let sessionId = event.sessionId,
           let session = sessions.first(where: { $0.id == sessionId }) {
            session.status = .allowedExit
            session.endAt = .now
            session.failedReason = nil
        }

        try context.save()
    }

    func addTag(name: String, context: ModelContext) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        context.insert(
            Tag(
                tagPublicId: "tag-\(UUID().uuidString.prefix(8))",
                uidHash: UUID().uuidString.lowercased(),
                name: clean,
                status: .archived
            )
        )
        try context.save()
    }

    func activateTag(_ tag: Tag, tags: [Tag], context: ModelContext) throws {
        for current in tags {
            current.status = current.id == tag.id ? .active : .archived
        }
        try context.save()
    }

    func updateShieldSelection(
        policy: ShieldPolicy,
        app: String,
        isSelected: Bool,
        context: ModelContext
    ) throws {
        var apps = Set(policy.selectedApps)
        if isSelected {
            apps.insert(app)
        } else {
            apps.remove(app)
        }
        policy.selectedApps = apps.sorted()
        try context.save()
    }

    func updateShieldEnabled(
        policy: ShieldPolicy,
        enabled: Bool,
        context: ModelContext
    ) throws {
        policy.enabled = enabled
        policy.updatedAt = .now
        try context.save()
    }

    func updateShieldActivitySelection(
        policy: ShieldPolicy,
        encodedSelection: Data?,
        summary: [String],
        context: ModelContext
    ) throws {
        policy.activitySelectionData = encodedSelection
        policy.selectedApps = summary
        policy.updatedAt = .now
        try context.save()
    }

    func manualExitRules(context: ModelContext) -> [PrecedentRule] {
        let descriptor = FetchDescriptor<PrecedentRule>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let allRules = (try? context.fetch(descriptor)) ?? []
        var seenKeys = Set<String>()

        return allRules.filter { rule in
            guard rule.violationType == .manualExit,
                  rule.decision == .allowForever,
                  rule.reasonKey.isEmpty == false,
                  seenKeys.insert(rule.reasonKey).inserted
            else {
                return false
            }
            return true
        }
    }

    func tagSnapshot(context: ModelContext, now: Date = .now) -> NFCTagSnapshot {
        let sessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let appointments = fetchAppointments(context: context)
        let nodes = (try? context.fetch(FetchDescriptor<ChainNode>())) ?? []
        let activeSession = activeSession(from: sessions)
        let latestMainProof = latestHash(in: nodes, chainType: .main)
        let sessionState: NFCTagSnapshot.SessionState

        switch activeSession?.status {
        case .running:
            sessionState = .run
        case .awaitingNFCCompletion:
            sessionState = .wait
        default:
            sessionState = .idle
        }

        return NFCTagSnapshot(
            mainChainLength: chainLengthForSessions(sessions),
            appointmentChainLength: chainLengthForAppointments(appointments),
            proofSnippet: String(latestMainProof.prefix(12)),
            sessionState: sessionState,
            unixTimestamp: Int(now.timeIntervalSince1970),
            durationMinutes: (activeSession?.durationSec ?? 0) / 60,
            sessionToken: activeSession?.id.uuidString.lowercased() ?? latestSessionToken(from: sessions)
        )
    }

    func expireOverdueAppointments(context: ModelContext, now: Date) throws {
        let appointments = fetchAppointments(context: context)
        let rules = try context.fetch(FetchDescriptor<PrecedentRule>())

        for appointment in appointments where appointment.status == .scheduled && appointment.windowEndAt < now {
            appointment.status = .missed
            let event = ViolationEvent(
                appointmentId: appointment.id,
                type: .appointmentMissed,
                payload: "预约开始于 \(appointment.scheduledStartAt.formatted(date: .omitted, time: .shortened))，窗口已过期"
            )
            if rules.contains(where: { $0.violationType == .appointmentMissed && $0.decision == .allowForever }) {
                event.decisionStatus = .allowed
                event.resolvedAt = now
                event.note = "已有永久允许规则，自动放行"
            }
            context.insert(event)
        }
    }

    private func recordViolation(
        type: ViolationType,
        payload: String,
        session: FocusSession?,
        appointment: Appointment?,
        context: ModelContext
    ) throws {
        guard type.isDeprecated == false else { return }

        let rules = try context.fetch(FetchDescriptor<PrecedentRule>())
        let autoAllow =
            type == .manualExit
            ? false
            : rules.contains(where: { $0.violationType == type && $0.decision == .allowForever })

        let recentFetch = FetchDescriptor<ViolationEvent>()
        let recentEvents = try context.fetch(recentFetch)
        let isDuplicate = recentEvents.contains {
            $0.type == type &&
            $0.sessionId == session?.id &&
            abs($0.createdAt.timeIntervalSinceNow) < 5
        }
        guard !isDuplicate else { return }

        let event = ViolationEvent(
            sessionId: session?.id,
            appointmentId: appointment?.id,
            type: type,
            payload: payload,
            decisionStatus: autoAllow ? .allowed : .pending,
            resolvedAt: autoAllow ? .now : nil,
            note: autoAllow ? "已有永久允许规则，自动放行" : ""
        )
        context.insert(event)

        if autoAllow == false, type == .appointmentMissed {
            let rule = PrecedentRule(
                violationType: type,
                decision: .reset,
                scope: "mvp-v1",
                note: "预约违约默认记为断链待确认"
            )
            context.insert(rule)
            event.decisionStatus = .reset
            event.resolvedRuleId = rule.id
            event.resolvedAt = .now
            event.note = "预约链断开"
        }

        try context.save()
    }

    private func purgeDeprecatedViolationArtifacts(context: ModelContext) throws {
        let events = try context.fetch(FetchDescriptor<ViolationEvent>())
        let rules = try context.fetch(FetchDescriptor<PrecedentRule>())

        for event in events where event.type.isDeprecated {
            context.delete(event)
        }

        for rule in rules where rule.violationType.isDeprecated {
            context.delete(rule)
        }
    }

    private func fetchAppointments(context: ModelContext) -> [Appointment] {
        let descriptor = FetchDescriptor<Appointment>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func currentChainSessions(from sessions: [FocusSession]) -> [FocusSession] {
        let orderedSessions = sessions.sorted { $0.startAt > $1.startAt }
        var streak: [FocusSession] = []

        for session in orderedSessions {
            switch session.status {
            case .completed:
                streak.append(session)
            case .failed:
                return streak.sorted { $0.startAt < $1.startAt }
            case .ready, .running, .awaitingNFCCompletion, .allowedExit:
                continue
            }
        }

        return streak.sorted { $0.startAt < $1.startAt }
    }

    private func chainLengthForSessions(_ sessions: [FocusSession]) -> Int {
        currentChainSessions(from: sessions).count
    }

    private func chainLengthForAppointments(_ appointments: [Appointment]) -> Int {
        appointments.sorted { $0.scheduledStartAt > $1.scheduledStartAt }
            .reduce(into: (count: 0, stop: false)) { state, appointment in
                guard !state.stop else { return }
                switch appointment.status {
                case .fulfilled:
                    state.count += 1
                case .missed:
                    state.stop = true
                case .scheduled:
                    break
                }
            }.count
    }

    private func latestHash(in nodes: [ChainNode], chainType: ChainType) -> String {
        nodes.filter { $0.chainType == chainType }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.proofHash ?? "GENESIS"
    }

    private func shortChainTitle(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "未命名专注" }
        guard trimmed.count > 12 else { return trimmed }
        return String(trimmed.prefix(12)) + "…"
    }

    private func proofHash(previousHash: String, components: [String]) -> String {
        let raw = ([previousHash] + components).joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func parseWebInvocationRoute(_ url: URL) -> InvocationRoute? {
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 2, pathParts[0] == invocationPathPrefix else { return nil }

        let publicId = normalizedPublicID(pathParts[1])
        guard !publicId.isEmpty else { return nil }

        return InvocationRoute(
            publicId: publicId,
            clipCompleted: queryValue(named: "clip_completed", in: url) == "1",
            clipDurationMinutes: Int(queryValue(named: "clip_duration", in: url) ?? "")
        )
    }

    private func parseFullAppHandoffRoute(_ url: URL) -> InvocationRoute? {
        guard url.host?.lowercased() == fullAppHandoffHost else { return nil }

        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard let firstPart = pathParts.first else { return nil }

        let publicId = normalizedPublicID(firstPart)
        guard !publicId.isEmpty else { return nil }

        return InvocationRoute(
            publicId: publicId,
            clipCompleted: queryValue(named: "clip_completed", in: url) == "1",
            clipDurationMinutes: Int(queryValue(named: "clip_duration", in: url) ?? "")
        )
    }

    private func baseURL(for configuration: AppConfiguration) -> URL? {
        baseComponents(for: configuration)?.url
    }

    private func baseComponents(for configuration: AppConfiguration) -> URLComponents? {
        let host = configuration.invocationHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components
    }

    private func normalizedPublicID(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private func manualExitRule(reasonKey: String, context: ModelContext) -> PrecedentRule? {
        manualExitRules(context: context).first(where: { $0.reasonKey == reasonKey })
    }

    private func normalizedManualExitReason(_ rawValue: String?) -> String {
        FocusDomainLogic.normalizedManualExitReason(rawValue)
    }

    private func cleanedManualExitReason(_ rawValue: String?) -> String {
        FocusDomainLogic.cleanedManualExitReason(rawValue)
    }

    private func latestSessionToken(from sessions: [FocusSession]) -> String {
        let latestSession = sessions.sorted { $0.startAt > $1.startAt }.first
        return String((latestSession?.id.uuidString.lowercased() ?? "none").prefix(8))
    }
}
