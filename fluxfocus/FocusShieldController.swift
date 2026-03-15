// [IN]: Combine, FamilyControls, ManagedSettings, and persisted ShieldPolicy snapshots / Combine、FamilyControls、ManagedSettings 与持久化 ShieldPolicy 快照
// [OUT]: Authorization state, picker selection, live Focus Shield application, and test-safe fallback behavior / 授权状态、选择器状态、实时 Focus Shield 应用与测试安全回退行为
// [POS]: Bridge from local policy state to Apple Screen Time shielding APIs without forcing tests through device-only services / 从本地策略状态到 Apple 屏幕使用时间屏蔽 API 的桥接层，并避免测试强行进入仅设备可用服务
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import Combine
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class FocusShieldController: ObservableObject {
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published var activitySelection: FamilyActivitySelection
    @Published var isPickerPresented = false
    @Published var lastErrorMessage: String?

    private let authorizationCenter: AuthorizationCenter?
    private let store: ManagedSettingsStore?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(testing: Bool = false) {
        if testing {
            authorizationCenter = nil
            store = nil
            authorizationStatus = .notDetermined
        } else {
            let center = AuthorizationCenter.shared
            authorizationCenter = center
            store = ManagedSettingsStore(named: .init("FocusShield"))
            authorizationStatus = center.authorizationStatus
        }
        activitySelection = FamilyActivitySelection()
    }

    var requiresAuthorization: Bool {
        authorizationStatus != .approved
    }

    var selectedApplicationTokens: [ApplicationToken] {
        Array(activitySelection.applicationTokens)
    }

    var selectedCategoryTokens: [ActivityCategoryToken] {
        Array(activitySelection.categoryTokens)
    }

    var selectedWebDomainTokens: [WebDomainToken] {
        Array(activitySelection.webDomainTokens)
    }

    var selectionSummary: [String] {
        var segments: [String] = []
        if activitySelection.applicationTokens.isEmpty == false {
            segments.append("App \(activitySelection.applicationTokens.count)")
        }
        if activitySelection.categoryTokens.isEmpty == false {
            segments.append("分类 \(activitySelection.categoryTokens.count)")
        }
        if activitySelection.webDomainTokens.isEmpty == false {
            segments.append("网站 \(activitySelection.webDomainTokens.count)")
        }
        return segments
    }

    func restoreSelection(from policy: ShieldPolicy?) {
        authorizationStatus = authorizationCenter?.authorizationStatus ?? .notDetermined
        guard let data = policy?.activitySelectionData,
              let selection = try? decoder.decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        if selection != activitySelection {
            activitySelection = selection
        }
    }

    func persistableSelectionData() -> Data? {
        try? encoder.encode(activitySelection)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard let authorizationCenter else {
            authorizationStatus = .notDetermined
            lastErrorMessage = nil
            return false
        }

        authorizationStatus = authorizationCenter.authorizationStatus
        guard authorizationStatus != .approved else { return true }

        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
            lastErrorMessage = nil
            return authorizationStatus == .approved
        } catch {
            authorizationStatus = authorizationCenter.authorizationStatus
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func beginSelectionFlow() async -> Bool {
        let isAuthorized = await requestAuthorizationIfNeeded()
        guard isAuthorized else { return false }
        isPickerPresented = true
        return true
    }

    func applyShield(isEnabled: Bool, isSessionRunning: Bool) {
        guard let store, isEnabled, isSessionRunning else {
            clearShield()
            return
        }

        store.shield.applications = activitySelection.applicationTokens.isEmpty ? nil : activitySelection.applicationTokens
        store.shield.applicationCategories = activitySelection.categoryTokens.isEmpty ? nil : .specific(activitySelection.categoryTokens)
        store.shield.webDomains = activitySelection.webDomainTokens.isEmpty ? nil : activitySelection.webDomainTokens
        store.shield.webDomainCategories = activitySelection.categoryTokens.isEmpty ? nil : .specific(activitySelection.categoryTokens)
    }

    func clearShield() {
        store?.clearAllSettings()
    }
}
