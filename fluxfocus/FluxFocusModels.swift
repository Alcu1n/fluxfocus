// [IN]: Foundation and SwiftData model macros / Foundation 与 SwiftData 模型宏
// [OUT]: Persistent entities plus lightweight dashboard, NFC snapshot, session, and visibility-aware violation value types / 持久化实体，以及轻量看板、NFC 快照、会话与带可见性语义的违规值类型
// [POS]: Canonical local schema for tags, sessions, violations, precedent reasons, configuration, and derived home-chain data / 标签、会话、违规、判例原因、配置与派生首页链条数据的本地规范数据模式
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import Foundation
import SwiftData

enum FocusSessionStatus: String, Codable, CaseIterable {
    case ready
    case running
    case awaitingNFCCompletion
    case completed
    case allowedExit
    case failed

    var isActive: Bool {
        switch self {
        case .running, .awaitingNFCCompletion:
            true
        case .ready, .completed, .allowedExit, .failed:
            false
        }
    }
}

enum SessionSource: String, Codable, CaseIterable {
    case nfcInvocation
    case quickStart
    case appointment

    var label: String {
        switch self {
        case .nfcInvocation: "NFC"
        case .quickStart: "快速开始"
        case .appointment: "预约履约"
        }
    }
}

enum ChainType: String, Codable, CaseIterable {
    case main
    case appointment

    var label: String {
        switch self {
        case .main: "主链"
        case .appointment: "预约链"
        }
    }
}

enum ViolationType: String, Codable, CaseIterable, Identifiable {
    case manualExit
    case longBackground
    case blockedAppAttempt
    case qualityFailure
    case appointmentMissed

    var id: String { rawValue }

    var isDeprecated: Bool {
        self == .longBackground
    }

    var isUserVisible: Bool {
        !isDeprecated
    }

    var label: String {
        switch self {
        case .manualExit: "主动退出"
        case .longBackground: "长时离开前台"
        case .blockedAppAttempt: "尝试打开被屏蔽 App"
        case .qualityFailure: "人工标记状态不合格"
        case .appointmentMissed: "预约未履约"
        }
    }

    var suggestion: String {
        switch self {
        case .manualExit: "降低单次时长，先保证完成率，再逐步拉长。"
        case .longBackground: "开始前清空外部打断源，并缩短离开前台容忍度。"
        case .blockedAppAttempt: "把高诱惑 App 放进默认黑名单，减少临场选择。"
        case .qualityFailure: "为会话写明确输出标准，避免完成后仍觉得不合格。"
        case .appointmentMissed: "预约时只做一个最小承诺，确保能按时触发主链。"
        }
    }
}

enum ViolationDecisionStatus: String, Codable, CaseIterable {
    case pending
    case reset
    case allowed
}

enum PrecedentDecision: String, Codable, CaseIterable {
    case reset
    case allowForever

    var label: String {
        switch self {
        case .reset: "断链重置"
        case .allowForever: "永久允许"
        }
    }
}

enum AppointmentStatus: String, Codable, CaseIterable {
    case scheduled
    case fulfilled
    case missed
}

enum TagStatus: String, Codable, CaseIterable {
    case active
    case archived
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var tagPublicId: String
    var uidHash: String
    var name: String
    var statusRaw: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        tagPublicId: String,
        uidHash: String,
        name: String,
        status: TagStatus = .active,
        createdAt: Date = .now
    ) {
        self.id = id
        self.tagPublicId = tagPublicId
        self.uidHash = uidHash
        self.name = name
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
    }

    var status: TagStatus {
        get { TagStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var tagPublicId: String
    var tagName: String
    var goal: String
    var durationSec: Int
    var startAt: Date
    var endAt: Date?
    var statusRaw: String
    var sourceRaw: String
    var shieldEnabled: Bool
    var failedReason: String?

    init(
        id: UUID = UUID(),
        tagPublicId: String,
        tagName: String,
        goal: String,
        durationSec: Int,
        startAt: Date = .now,
        endAt: Date? = nil,
        status: FocusSessionStatus,
        source: SessionSource,
        shieldEnabled: Bool,
        failedReason: String? = nil
    ) {
        self.id = id
        self.tagPublicId = tagPublicId
        self.tagName = tagName
        self.goal = goal
        self.durationSec = durationSec
        self.startAt = startAt
        self.endAt = endAt
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.shieldEnabled = shieldEnabled
        self.failedReason = failedReason
    }

    var status: FocusSessionStatus {
        get { FocusSessionStatus(rawValue: statusRaw) ?? .ready }
        set { statusRaw = newValue.rawValue }
    }

    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .quickStart }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class Appointment {
    @Attribute(.unique) var id: UUID
    var tagPublicId: String
    var tagName: String
    var goal: String
    var durationSec: Int
    var createdAt: Date
    var scheduledStartAt: Date
    var windowEndAt: Date
    var statusRaw: String
    var fulfilledSessionId: UUID?

    init(
        id: UUID = UUID(),
        tagPublicId: String,
        tagName: String,
        goal: String,
        durationSec: Int,
        createdAt: Date = .now,
        scheduledStartAt: Date,
        windowEndAt: Date,
        status: AppointmentStatus = .scheduled,
        fulfilledSessionId: UUID? = nil
    ) {
        self.id = id
        self.tagPublicId = tagPublicId
        self.tagName = tagName
        self.goal = goal
        self.durationSec = durationSec
        self.createdAt = createdAt
        self.scheduledStartAt = scheduledStartAt
        self.windowEndAt = windowEndAt
        self.statusRaw = status.rawValue
        self.fulfilledSessionId = fulfilledSessionId
    }

    var status: AppointmentStatus {
        get { AppointmentStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class ChainNode {
    @Attribute(.unique) var id: UUID
    var chainTypeRaw: String
    var nodeIndex: Int
    var relatedEntityId: String
    var proofHash: String
    var summary: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        chainType: ChainType,
        nodeIndex: Int,
        relatedEntityId: String,
        proofHash: String,
        summary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.chainTypeRaw = chainType.rawValue
        self.nodeIndex = nodeIndex
        self.relatedEntityId = relatedEntityId
        self.proofHash = proofHash
        self.summary = summary
        self.createdAt = createdAt
    }

    var chainType: ChainType {
        get { ChainType(rawValue: chainTypeRaw) ?? .main }
        set { chainTypeRaw = newValue.rawValue }
    }
}

@Model
final class ViolationEvent {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID?
    var appointmentId: UUID?
    var typeRaw: String
    var payload: String
    var createdAt: Date
    var decisionStatusRaw: String
    var resolvedAt: Date?
    var resolvedRuleId: UUID?
    var decisionReasonKey: String
    var decisionReasonText: String
    var note: String

    init(
        id: UUID = UUID(),
        sessionId: UUID? = nil,
        appointmentId: UUID? = nil,
        type: ViolationType,
        payload: String,
        createdAt: Date = .now,
        decisionStatus: ViolationDecisionStatus = .pending,
        resolvedAt: Date? = nil,
        resolvedRuleId: UUID? = nil,
        decisionReasonKey: String = "",
        decisionReasonText: String = "",
        note: String = ""
    ) {
        self.id = id
        self.sessionId = sessionId
        self.appointmentId = appointmentId
        self.typeRaw = type.rawValue
        self.payload = payload
        self.createdAt = createdAt
        self.decisionStatusRaw = decisionStatus.rawValue
        self.resolvedAt = resolvedAt
        self.resolvedRuleId = resolvedRuleId
        self.decisionReasonKey = decisionReasonKey
        self.decisionReasonText = decisionReasonText
        self.note = note
    }

    var type: ViolationType {
        get { ViolationType(rawValue: typeRaw) ?? .manualExit }
        set { typeRaw = newValue.rawValue }
    }

    var decisionStatus: ViolationDecisionStatus {
        get { ViolationDecisionStatus(rawValue: decisionStatusRaw) ?? .pending }
        set { decisionStatusRaw = newValue.rawValue }
    }
}

@Model
final class PrecedentRule {
    @Attribute(.unique) var id: UUID
    var violationTypeRaw: String
    var decisionRaw: String
    var scope: String
    var createdAt: Date
    var reasonKey: String
    var reasonText: String
    var note: String

    init(
        id: UUID = UUID(),
        violationType: ViolationType,
        decision: PrecedentDecision,
        scope: String,
        createdAt: Date = .now,
        reasonKey: String = "",
        reasonText: String = "",
        note: String = ""
    ) {
        self.id = id
        self.violationTypeRaw = violationType.rawValue
        self.decisionRaw = decision.rawValue
        self.scope = scope
        self.createdAt = createdAt
        self.reasonKey = reasonKey
        self.reasonText = reasonText
        self.note = note
    }

    var violationType: ViolationType {
        get { ViolationType(rawValue: violationTypeRaw) ?? .manualExit }
        set { violationTypeRaw = newValue.rawValue }
    }

    var decision: PrecedentDecision {
        get { PrecedentDecision(rawValue: decisionRaw) ?? .reset }
        set { decisionRaw = newValue.rawValue }
    }
}

@Model
final class ShieldPolicy {
    @Attribute(.unique) var id: UUID
    var selectedAppsBlob: String
    var activitySelectionData: Data?
    var enabled: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        selectedApps: [String],
        activitySelectionData: Data? = nil,
        enabled: Bool = true,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.selectedAppsBlob = selectedApps.joined(separator: "|")
        self.activitySelectionData = activitySelectionData
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    var selectedApps: [String] {
        get {
            selectedAppsBlob
                .split(separator: "|")
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        set {
            selectedAppsBlob = newValue.joined(separator: "|")
            updatedAt = .now
        }
    }
}

struct SessionDraft {
    var goal: String = "完成一段不被打断的深度工作"
    var durationMinutes: Int = 25
    var shieldEnabled: Bool = true
}

struct DashboardMetrics {
    var focusSecondsToday: Int
    var completedThisWeek: Int
    var mainChainLength: Int
    var appointmentChainLength: Int
    var breakCount: Int
    var shieldBlocks: Int
}

struct HomeChainVisualNode: Identifiable {
    let id: UUID
    let chainIndex: Int
    let title: String
    let durationSec: Int
    let completedAt: Date
    let proofSnippet: String
}

struct HomeChainDailyPulse: Identifiable {
    let dayStart: Date
    let totalFocusSeconds: Int
    let completedCount: Int
    let contributesToCurrentChain: Bool

    var id: Date { dayStart }
}

struct HomeChainSnapshot {
    let currentLength: Int
    let archivedLength: Int
    let totalCompletedSessions: Int
    let totalFocusSeconds: Int
    let focusSecondsToday: Int
    let todayContributionCount: Int
    let shieldedSessionCount: Int
    let latestSummary: String
    let latestCompletionAt: Date?
    let recentNodes: [HomeChainVisualNode]
    let dailyPulses: [HomeChainDailyPulse]
}

@Model
final class AppConfiguration {
    @Attribute(.unique) var id: UUID
    var invocationHost: String
    var signatureSalt: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        invocationHost: String,
        signatureSalt: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.invocationHost = invocationHost
        // Keep the legacy field to avoid a destructive local migration.
        self.signatureSalt = signatureSalt
        self.updatedAt = updatedAt
    }
}

struct NFCTagSnapshot: Equatable {
    enum SessionState: String, CaseIterable {
        case idle
        case run
        case wait
    }

    static let version = "ff1"

    var mainChainLength: Int
    var appointmentChainLength: Int
    var proofSnippet: String
    var sessionState: SessionState
    var unixTimestamp: Int
    var durationMinutes: Int
    var sessionToken: String

    init(
        mainChainLength: Int,
        appointmentChainLength: Int,
        proofSnippet: String,
        sessionState: SessionState,
        unixTimestamp: Int,
        durationMinutes: Int,
        sessionToken: String
    ) {
        self.mainChainLength = max(0, mainChainLength)
        self.appointmentChainLength = max(0, appointmentChainLength)
        self.proofSnippet = Self.sanitizeProofSnippet(proofSnippet)
        self.sessionState = sessionState
        self.unixTimestamp = max(0, unixTimestamp)
        self.durationMinutes = max(0, durationMinutes)
        self.sessionToken = Self.sanitizeSessionToken(sessionToken)
    }

    init?(encodedString: String) {
        let parts = encodedString.split(separator: "|").map(String.init)
        guard parts.first == Self.version else { return nil }

        var values: [String: String] = [:]
        for part in parts.dropFirst() {
            let segments = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard segments.count == 2 else { continue }
            values[segments[0]] = segments[1]
        }

        guard
            let mainChain = Int(values["m"] ?? ""),
            let appointmentChain = Int(values["a"] ?? ""),
            let proofSnippet = values["p"],
            let stateRaw = values["s"],
            let sessionState = SessionState(rawValue: stateRaw),
            let unixTimestamp = Int(values["t"] ?? ""),
            let durationMinutes = Int(values["d"] ?? ""),
            let sessionToken = values["x"]
        else {
            return nil
        }

        self.init(
            mainChainLength: mainChain,
            appointmentChainLength: appointmentChain,
            proofSnippet: proofSnippet,
            sessionState: sessionState,
            unixTimestamp: unixTimestamp,
            durationMinutes: durationMinutes,
            sessionToken: sessionToken
        )
    }

    var encodedString: String {
        [
            Self.version,
            "m=\(mainChainLength)",
            "a=\(appointmentChainLength)",
            "p=\(Self.sanitizeProofSnippet(proofSnippet))",
            "s=\(sessionState.rawValue)",
            "t=\(unixTimestamp)",
            "d=\(durationMinutes)",
            "x=\(Self.sanitizeSessionToken(sessionToken))",
        ].joined(separator: "|")
    }

    var summaryLines: [String] {
        [
            "Snapshot \(Self.version)",
            "主链 \(mainChainLength) · 预约链 \(appointmentChainLength)",
            "状态 \(sessionState.rawValue) · 时长 \(durationMinutes) 分钟",
            "Proof \(proofSnippet)",
            "会话 \(sessionToken)"
        ]
    }

    private static func sanitizeProofSnippet(_ rawValue: String) -> String {
        let filtered = rawValue.filter(\.isASCII)
        let fallback = filtered.isEmpty ? "GENESIS" : filtered
        return String(fallback.prefix(12))
    }

    private static func sanitizeSessionToken(_ rawValue: String) -> String {
        let filtered = rawValue.filter(\.isASCII)
        let fallback = filtered.isEmpty ? "none" : filtered
        return String(fallback.prefix(8))
    }
}
