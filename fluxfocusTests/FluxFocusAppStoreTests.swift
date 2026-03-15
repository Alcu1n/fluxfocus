// [IN]: XCTest and the full app module under test / XCTest 与被测完整应用模块
// [OUT]: Deterministic unit coverage for NFC-governed lifecycle rules, precedent normalization, snapshot encoding, and violation visibility contracts / 覆盖 NFC 治理生命周期规则、判例归一化、快照编码与违规可见性契约的确定性单测
// [POS]: Fast contract checks for pure domain paths that should not regress during UI or persistence iteration / 在 UI 或持久化持续迭代时不应回归的纯领域路径快速契约检查
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import XCTest
@testable import fluxfocus

@MainActor
final class FluxFocusAppStoreTests: XCTestCase {
    func testLifecyclePlanTransitionsRunningToAwaitingThenCompleted() {
        XCTAssertEqual(
            FocusDomainLogic.lifecyclePlan(for: .running, currentMainChainCount: 7),
            SessionLifecyclePlan(
                targetStatus: .awaitingNFCCompletion,
                closesSession: false,
                nextMainChainNodeIndex: nil
            )
        )
        XCTAssertEqual(
            FocusDomainLogic.lifecyclePlan(for: .awaitingNFCCompletion, currentMainChainCount: 7),
            SessionLifecyclePlan(
                targetStatus: .completed,
                closesSession: true,
                nextMainChainNodeIndex: 8
            )
        )
        XCTAssertNil(FocusDomainLogic.lifecyclePlan(for: .allowedExit, currentMainChainCount: 7))
    }

    func testManualExitReasonResolutionReusesExistingRuleAndCollapsesWhitespace() {
        let existingRule = ManualExitRuleDigest(
            reasonKey: "家里有急事",
            reasonText: "家里有急事"
        )
        let resolution = FocusDomainLogic.manualExitReasonResolution(
            "  家里  有急事  ",
            existingRules: [existingRule]
        )
        XCTAssertEqual(
            resolution,
            ManualExitReasonResolution(
                key: "家里有急事",
                text: "家里有急事",
                reusesExistingRule: true
            )
        )
        XCTAssertNil(FocusDomainLogic.manualExitReasonResolution("   ", existingRules: [existingRule]))
    }

    func testNFCTagSnapshotRoundTripsAndKeepsURLRecordFirst() throws {
        let snapshot = NFCTagSnapshot(
            mainChainLength: 12,
            appointmentChainLength: 3,
            proofSnippet: "abcdef1234567890",
            sessionState: .wait,
            unixTimestamp: 1_710_000_000,
            durationMinutes: 45,
            sessionToken: "1234567890abcdef"
        )

        let decoded = try XCTUnwrap(NFCTagSnapshot(encodedString: snapshot.encodedString))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertLessThan(snapshot.encodedString.utf8.count, 96)

        let url = try XCTUnwrap(URL(string: "https://fluxfocusclip.lraitech.com/i/desk-altar-001"))
        let message = try NFCManager.ndefMessage(url: url, snapshot: snapshot)
        XCTAssertEqual(message.records.count, 2)
        XCTAssertEqual(message.records.first?.wellKnownTypeURIPayload(), url)
        XCTAssertEqual(message.records[1].wellKnownTypeTextPayload().0, snapshot.encodedString)
    }

    func testSessionTagTouchDispositionCoversIdleRunningWaitingAndMismatch() throws {
        XCTAssertEqual(
            FocusDomainLogic.sessionTagTouchDisposition(
                SessionTouchContext(
                    scannedTagPublicId: "desk-altar-001",
                    activeSessionTagPublicId: nil,
                    activeSessionTagName: nil,
                    activeSessionStatus: nil
                )
            ),
            .enterSession
        )

        XCTAssertEqual(
            FocusDomainLogic.sessionTagTouchDisposition(
                SessionTouchContext(
                    scannedTagPublicId: "desk-altar-001",
                    activeSessionTagPublicId: "desk-altar-001",
                    activeSessionTagName: "主标签",
                    activeSessionStatus: .running
                )
            ),
            .triggerManualExit
        )
        XCTAssertEqual(
            FocusDomainLogic.sessionTagTouchDisposition(
                SessionTouchContext(
                    scannedTagPublicId: "desk-altar-002",
                    activeSessionTagPublicId: "desk-altar-001",
                    activeSessionTagName: "主标签",
                    activeSessionStatus: .running
                )
            ),
            .rejectMismatchedTag(expectedTagName: "主标签")
        )
        XCTAssertEqual(
            FocusDomainLogic.sessionTagTouchDisposition(
                SessionTouchContext(
                    scannedTagPublicId: "desk-altar-001",
                    activeSessionTagPublicId: "desk-altar-001",
                    activeSessionTagName: "主标签",
                    activeSessionStatus: .awaitingNFCCompletion
                )
            ),
            .completeAwaitingSession
        )
    }

    func testDeprecatedLongBackgroundViolationIsHiddenFromUIContracts() {
        XCTAssertTrue(ViolationType.longBackground.isDeprecated)
        XCTAssertFalse(ViolationType.longBackground.isUserVisible)
        XCTAssertTrue(ViolationType.manualExit.isUserVisible)
    }
}
