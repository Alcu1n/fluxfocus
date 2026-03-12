//
//  FluxFocusAppStore.swift
//  fluxfocus
//
//  Created by Codex on 2026/3/12.
//

import CryptoKit
import Foundation
import Observation
import SwiftData

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
    private var backgroundEnteredAt: Date?

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
                    invocationHost: "clip.example.com",
                    signatureSalt: "fluxfocus-mvp"
                )
            )
        }

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

    func invocationURL(for tag: Tag, configuration: AppConfiguration) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.invocationHost.trimmingCharacters(in: .whitespacesAndNewlines)
        components.path = "/i/\(tag.tagPublicId)"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "s", value: signature(for: tag.tagPublicId, salt: configuration.signatureSalt))
        ]
        return components.url
    }

    func parseInvocationURL(_ url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 2, pathParts[0] == "i" else { return nil }
        let version = components?.queryItems?.first(where: { $0.name == "v" })?.value
        guard version == "1" else { return nil }
        return pathParts[1]
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

    func simulateScenePhaseChange(
        from oldPhase: String,
        to newPhase: String,
        sessions: [FocusSession],
        context: ModelContext
    ) throws {
        guard let running = runningSession(from: sessions) else {
            backgroundEnteredAt = nil
            return
        }

        if oldPhase == "active", newPhase != "active" {
            backgroundEnteredAt = .now
            return
        }

        if oldPhase != "active", newPhase == "active", let backgroundEnteredAt {
            let delta = Int(Date.now.timeIntervalSince(backgroundEnteredAt))
            self.backgroundEnteredAt = nil
            if delta >= 45 {
                try recordViolation(
                    type: .longBackground,
                    payload: "离开前台 \(delta) 秒",
                    session: running,
                    appointment: nil,
                    context: context
                )
            }
        }
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
        guard runningSession(from: sessions) == nil else { return }

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

    func completeSession(
        _ session: FocusSession,
        sessions: [FocusSession],
        nodes: [ChainNode],
        context: ModelContext
    ) throws {
        guard session.status == .running else { return }

        let nextIndex = chainLengthForSessions(sessions) + 1
        session.status = .completed
        session.endAt = .now

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

    func abandonSession(
        _ session: FocusSession,
        context: ModelContext
    ) throws {
        try recordViolation(
            type: .manualExit,
            payload: "用户主动结束当前会话",
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
        sessions: [FocusSession],
        context: ModelContext
    ) throws {
        let rule = PrecedentRule(
            violationType: event.type,
            decision: decision,
            scope: "mvp-v1",
            note: decision == .allowForever ? "后续相同类型自动放行" : "本次违规触发断链"
        )
        context.insert(rule)

        event.decisionStatus = decision == .reset ? .reset : .allowed
        event.resolvedAt = .now
        event.resolvedRuleId = rule.id
        event.note = decision.label

        if decision == .reset,
           let sessionId = event.sessionId,
           let session = sessions.first(where: { $0.id == sessionId }) {
            session.status = .failed
            session.endAt = .now
            session.failedReason = event.type.label
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
        let rules = try context.fetch(FetchDescriptor<PrecedentRule>())
        let autoAllow = rules.contains(where: { $0.violationType == type && $0.decision == .allowForever })

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

    private func fetchAppointments(context: ModelContext) -> [Appointment] {
        let descriptor = FetchDescriptor<Appointment>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func chainLengthForSessions(_ sessions: [FocusSession]) -> Int {
        sessions.sorted { $0.startAt > $1.startAt }
            .reduce(into: (count: 0, stop: false)) { state, session in
                guard !state.stop else { return }
                switch session.status {
                case .completed:
                    state.count += 1
                case .failed:
                    state.stop = true
                default:
                    break
                }
            }.count
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

    private func proofHash(previousHash: String, components: [String]) -> String {
        let raw = ([previousHash] + components).joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func signature(for publicId: String, salt: String) -> String {
        let raw = "\(publicId)|1|\(salt)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
