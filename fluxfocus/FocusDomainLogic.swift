// [IN]: Foundation plus shared focus enums and NFC touch dispositions / Foundation 以及共享专注枚举与 NFC 触碰分支
// [OUT]: Pure lifecycle, reason-normalization, and tag-routing helpers detached from SwiftData and Observation / 脱离 SwiftData 与 Observation 的纯生命周期、原因归一化与标签路由辅助逻辑
// [POS]: Stable domain contract layer for tests and store orchestration / 供测试与状态编排复用的稳定领域契约层
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import Foundation

struct SessionTouchContext: Equatable {
    let scannedTagPublicId: String
    let activeSessionTagPublicId: String?
    let activeSessionTagName: String?
    let activeSessionStatus: FocusSessionStatus?
}

struct ManualExitRuleDigest: Equatable {
    let reasonKey: String
    let reasonText: String
}

enum FocusDomainLogic {
    static func sessionTagTouchDisposition(
        _ context: SessionTouchContext
    ) -> SessionTagTouchDisposition {
        guard let activeStatus = context.activeSessionStatus,
              let activeTagPublicId = context.activeSessionTagPublicId,
              let activeTagName = context.activeSessionTagName else {
            return .enterSession
        }

        guard activeTagPublicId == context.scannedTagPublicId else {
            return .rejectMismatchedTag(expectedTagName: activeTagName)
        }

        switch activeStatus {
        case .running:
            return .triggerManualExit
        case .awaitingNFCCompletion:
            return .completeAwaitingSession
        case .ready, .completed, .allowedExit, .failed:
            return .enterSession
        }
    }

    static func lifecyclePlan(
        for status: FocusSessionStatus,
        currentMainChainCount: Int
    ) -> SessionLifecyclePlan? {
        switch status {
        case .running:
            SessionLifecyclePlan(
                targetStatus: .awaitingNFCCompletion,
                closesSession: false,
                nextMainChainNodeIndex: nil
            )
        case .awaitingNFCCompletion:
            SessionLifecyclePlan(
                targetStatus: .completed,
                closesSession: true,
                nextMainChainNodeIndex: currentMainChainCount + 1
            )
        case .ready, .completed, .allowedExit, .failed:
            nil
        }
    }

    static func manualExitReasonResolution(
        _ rawReason: String?,
        existingRules: [ManualExitRuleDigest]
    ) -> ManualExitReasonResolution? {
        let key = normalizedManualExitReason(rawReason)
        guard key.isEmpty == false else { return nil }

        let text = cleanedManualExitReason(rawReason)
        let existingRule = existingRules.first { rule in
            let existingKey =
                rule.reasonKey.isEmpty
                ? normalizedManualExitReason(rule.reasonText)
                : normalizedManualExitReason(rule.reasonKey)
            return existingKey == key
        }
        let resolvedKey = existingRule?.reasonKey.isEmpty == false ? existingRule?.reasonKey ?? key : key
        let resolvedText = existingRule?.reasonText.isEmpty == false ? existingRule?.reasonText ?? text : text

        return ManualExitReasonResolution(
            key: resolvedKey,
            text: resolvedText,
            reusesExistingRule: existingRule != nil
        )
    }

    static func normalizedManualExitReason(_ rawValue: String?) -> String {
        let collapsed = (rawValue ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.lowercased()
    }

    static func cleanedManualExitReason(_ rawValue: String?) -> String {
        (rawValue ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
