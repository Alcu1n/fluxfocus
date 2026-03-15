// [IN]: CoreNFC, Foundation, and local NFC tag snapshot models / CoreNFC、Foundation 与本地 NFC 标签快照模型
// [OUT]: Invocation scans, raw NDEF reads, URL+snapshot writes, foreground scan-rewrite transactions, and cancel-safe completion delivery / invocation 扫描、原始 NDEF 读取、URL+快照写入、前台扫描回写事务与取消安全的结果回传
// [POS]: Device-facing NFC bridge that keeps App Clip URL routing intact while optionally mirroring compact chain snapshots / 在保持 App Clip URL 路由不变的同时可选镜像紧凑链条快照的设备层 NFC 桥
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

@preconcurrency import CoreNFC
import Combine
import Foundation

struct NFCScanPayload {
    let uidHex: String
    let url: URL?
    let snapshot: NFCTagSnapshot?
    let rawRecords: [String]
    let writeWarning: String?

    func withWriteWarning(_ warning: String) -> NFCScanPayload {
        NFCScanPayload(
            uidHex: uidHex,
            url: url,
            snapshot: snapshot,
            rawRecords: rawRecords,
            writeWarning: warning
        )
    }
}

struct NFCNDEFWriteRequest {
    let url: URL
    let snapshot: NFCTagSnapshot?
    let successMessage: String
}

enum NFCManagerError: LocalizedError {
    case unavailable
    case busy
    case cancelled
    case multipleTags
    case unsupportedTag
    case emptyMessage
    case invalidURL
    case readOnly
    case notWritable
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前设备不支持 NFC 读写。"
        case .busy: "NFC 会话进行中，请稍后再试。"
        case .cancelled: "已取消 NFC 会话。"
        case .multipleTags: "请一次只贴近一张 NFC 标签。"
        case .unsupportedTag: "检测到的标签不支持 NDEF 读写。"
        case .emptyMessage: "标签中没有可读取的 NDEF 内容。"
        case .invalidURL: "标签中的 URL 无法解析。"
        case .readOnly: "该标签是只读状态，无法写入快照。"
        case .notWritable: "该标签当前不可写入。"
        case .payloadTooLarge: "写入内容超过标签容量。"
        }
    }
}

final class NFCManager: NSObject, ObservableObject {
    typealias RewriteHandler = @MainActor (NFCScanPayload) -> NFCNDEFWriteRequest?

    @Published var statusMessage = "待机"
    @Published var lastPayloadSummary = ""

    private var session: NFCTagReaderSession?
    private var operation: Operation?
    private var isClosingSession = false

    private enum Operation {
        case scanInvocation(prompt: String, rewrite: RewriteHandler?, completion: (Result<NFCScanPayload, Error>) -> Void)
        case readRaw(prompt: String, completion: (Result<NFCScanPayload, Error>) -> Void)
        case writeURL(prompt: String, url: URL, snapshot: NFCTagSnapshot?, completion: (Result<NFCScanPayload, Error>) -> Void)

        var prompt: String {
            switch self {
            case .scanInvocation(let prompt, _, _):
                prompt
            case .readRaw(let prompt, _):
                prompt
            case .writeURL(let prompt, _, _, _):
                prompt
            }
        }
    }

    private struct SendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    func beginInvocationScan(
        prompt: String = "将 iPhone 顶部靠近已写入的 FluxFocus NFC 标签",
        rewriteHandler: RewriteHandler? = nil,
        completion: @escaping (Result<NFCScanPayload, Error>) -> Void
    ) {
        startSession(
            operation: .scanInvocation(
                prompt: prompt,
                rewrite: rewriteHandler,
                completion: completion
            )
        )
    }

    func beginRawRead(completion: @escaping (Result<NFCScanPayload, Error>) -> Void) {
        startSession(
            operation: .readRaw(
                prompt: "将 iPhone 顶部靠近 NFC 标签以读取内容",
                completion: completion
            )
        )
    }

    func beginWrite(
        url: URL,
        snapshot: NFCTagSnapshot? = nil,
        completion: @escaping (Result<NFCScanPayload, Error>) -> Void
    ) {
        startSession(
            operation: .writeURL(
                prompt: "将空白或可写的 NFC 标签贴近 iPhone 进行写入",
                url: url,
                snapshot: snapshot,
                completion: completion
            )
        )
    }

    private func startSession(operation: Operation) {
        guard NFCTagReaderSession.readingAvailable else {
            statusMessage = NFCManagerError.unavailable.localizedDescription
            deliver(result: .failure(NFCManagerError.unavailable), alertMessage: nil)
            return
        }

        guard session == nil else {
            statusMessage = NFCManagerError.busy.localizedDescription
            deliver(result: .failure(NFCManagerError.busy), alertMessage: nil)
            return
        }

        self.operation = operation
        statusMessage = operation.prompt

        guard let readerSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self
        ) else {
            statusMessage = NFCManagerError.unavailable.localizedDescription
            deliver(result: .failure(NFCManagerError.unavailable), alertMessage: nil)
            return
        }

        readerSession.alertMessage = operation.prompt
        readerSession.begin()
        session = readerSession
    }

    private func deliver(result: Result<NFCScanPayload, Error>, alertMessage: String?) {
        if let alertMessage {
            session?.alertMessage = alertMessage
        }

        let currentOperation = operation
        operation = nil
        session = nil
        isClosingSession = false

        switch result {
        case .success(let payload):
            var lines = payload.rawRecords
            if let warning = payload.writeWarning {
                lines.append("WARNING: \(warning)")
            }
            lastPayloadSummary = lines.joined(separator: "\n")
            statusMessage = "最近一次标签 UID: \(payload.uidHex)"
        case .failure(let error):
            statusMessage = error.localizedDescription
        }

        switch currentOperation {
        case .scanInvocation(_, _, let completion):
            completion(result)
        case .readRaw(_, let completion):
            completion(result)
        case .writeURL(_, _, _, let completion):
            completion(result)
        case nil:
            break
        }
    }

    private func finishReadSuccess(
        payload: NFCScanPayload,
        session: NFCTagReaderSession,
        alertMessage: String
    ) {
        isClosingSession = true
        session.alertMessage = alertMessage
        session.invalidate()
        DispatchQueue.main.async {
            self.deliver(result: .success(payload), alertMessage: alertMessage)
        }
    }

    private func finishReadSuccessWithWarning(
        payload: NFCScanPayload,
        warning: String,
        session: NFCTagReaderSession
    ) {
        isClosingSession = true
        session.alertMessage = "标签已识别，但快照未回写"
        session.invalidate()
        DispatchQueue.main.async {
            self.deliver(
                result: .success(payload.withWriteWarning(warning)),
                alertMessage: "标签已识别，但快照未回写"
            )
        }
    }

    private func fail(_ error: Error, session: NFCTagReaderSession, message: String? = nil) {
        isClosingSession = true
        session.invalidate(errorMessage: message ?? error.localizedDescription)
        DispatchQueue.main.async {
            self.deliver(result: .failure(error), alertMessage: nil)
        }
    }

    private func performWrite(
        request: NFCNDEFWriteRequest,
        uidHex: String,
        ndefTag: NFCNDEFTag,
        session: NFCTagReaderSession,
        basePayload: NFCScanPayload? = nil,
        degradeFailureToWarning: Bool
    ) {
        let sessionBox = SendableBox(value: session)
        let ndefTagBox = SendableBox(value: ndefTag)

        ndefTagBox.value.queryNDEFStatus { status, capacity, error in
            if let error {
                if degradeFailureToWarning, let basePayload {
                    self.finishReadSuccessWithWarning(
                        payload: basePayload,
                        warning: error.localizedDescription,
                        session: sessionBox.value
                    )
                } else {
                    self.fail(error, session: sessionBox.value)
                }
                return
            }

            guard status != .readOnly else {
                if degradeFailureToWarning, let basePayload {
                    self.finishReadSuccessWithWarning(
                        payload: basePayload,
                        warning: NFCManagerError.readOnly.localizedDescription,
                        session: sessionBox.value
                    )
                } else {
                    self.fail(NFCManagerError.readOnly, session: sessionBox.value)
                }
                return
            }

            guard status == .readWrite else {
                if degradeFailureToWarning, let basePayload {
                    self.finishReadSuccessWithWarning(
                        payload: basePayload,
                        warning: NFCManagerError.notWritable.localizedDescription,
                        session: sessionBox.value
                    )
                } else {
                    self.fail(NFCManagerError.notWritable, session: sessionBox.value)
                }
                return
            }

            let message: NFCNDEFMessage
            do {
                message = try Self.ndefMessage(url: request.url, snapshot: request.snapshot)
            } catch {
                if degradeFailureToWarning, let basePayload {
                    self.finishReadSuccessWithWarning(
                        payload: basePayload,
                        warning: error.localizedDescription,
                        session: sessionBox.value
                    )
                } else {
                    self.fail(error, session: sessionBox.value)
                }
                return
            }

            guard Self.estimatedSize(of: message) <= capacity else {
                if degradeFailureToWarning, let basePayload {
                    self.finishReadSuccessWithWarning(
                        payload: basePayload,
                        warning: NFCManagerError.payloadTooLarge.localizedDescription,
                        session: sessionBox.value
                    )
                } else {
                    self.fail(NFCManagerError.payloadTooLarge, session: sessionBox.value)
                }
                return
            }

            ndefTagBox.value.writeNDEF(message) { error in
                if let error {
                    if degradeFailureToWarning, let basePayload {
                        self.finishReadSuccessWithWarning(
                            payload: basePayload,
                            warning: error.localizedDescription,
                            session: sessionBox.value
                        )
                    } else {
                        self.fail(error, session: sessionBox.value)
                    }
                    return
                }

                let writtenPayload = NFCScanPayload(
                    uidHex: uidHex,
                    url: request.url,
                    snapshot: request.snapshot,
                    rawRecords: Self.rawRecords(url: request.url, snapshot: request.snapshot),
                    writeWarning: basePayload?.writeWarning
                )
                self.finishReadSuccess(
                    payload: writtenPayload,
                    session: sessionBox.value,
                    alertMessage: request.successMessage
                )
            }
        }
    }

    private static func readPayload(from message: NFCNDEFMessage, uidHex: String) -> NFCScanPayload {
        var url: URL?
        var snapshot: NFCTagSnapshot?
        var summaries: [String] = []

        for record in message.records {
            if let recordURL = record.wellKnownTypeURIPayload() {
                if url == nil {
                    url = recordURL
                }
                summaries.append(recordURL.absoluteString)
                continue
            }

            let textPayload = record.wellKnownTypeTextPayload()
            if let text = textPayload.0 {
                if snapshot == nil, let decodedSnapshot = NFCTagSnapshot(encodedString: text) {
                    snapshot = decodedSnapshot
                }
                summaries.append(text)
                continue
            }

            summaries.append("TNF=\(record.typeNameFormat.rawValue), \(record.payload.count) bytes")
        }

        return NFCScanPayload(
            uidHex: uidHex,
            url: url,
            snapshot: snapshot,
            rawRecords: summaries,
            writeWarning: nil
        )
    }

    private static func rawRecords(url: URL, snapshot: NFCTagSnapshot?) -> [String] {
        var lines = [url.absoluteString]
        if let snapshot {
            lines.append(snapshot.encodedString)
        }
        return lines
    }

    static func ndefMessage(url: URL, snapshot: NFCTagSnapshot?) throws -> NFCNDEFMessage {
        guard let urlPayload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            throw NFCManagerError.invalidURL
        }

        var records = [urlPayload]
        if let snapshot {
            guard let textPayload = NFCNDEFPayload.wellKnownTypeTextPayload(
                string: snapshot.encodedString,
                locale: Locale(identifier: "en")
            ) else {
                throw NFCManagerError.payloadTooLarge
            }
            records.append(textPayload)
        }
        return NFCNDEFMessage(records: records)
    }

    private static func estimatedSize(of message: NFCNDEFMessage) -> Int {
        message.records.reduce(0) { partialResult, record in
            partialResult + record.payload.count + record.identifier.count + record.type.count
        }
    }

    private static func identifierHex(for tag: NFCTag) -> String {
        switch tag {
        case .miFare(let tag):
            tag.identifier.map { String(format: "%02hhx", $0) }.joined()
        case .iso7816(let tag):
            tag.identifier.map { String(format: "%02hhx", $0) }.joined()
        case .feliCa(let tag):
            tag.currentIDm.map { String(format: "%02hhx", $0) }.joined()
        case .iso15693(let tag):
            tag.identifier.map { String(format: "%02hhx", $0) }.joined()
        @unknown default:
            UUID().uuidString.lowercased()
        }
    }

    private static func ndefTag(for tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let tag): tag
        case .iso7816(let tag): tag
        case .feliCa(let tag): tag
        case .iso15693(let tag): tag
        @unknown default: nil
        }
    }
}

extension NFCManager: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            if self.isClosingSession {
                self.isClosingSession = false
                return
            }

            let nsError = error as NSError
            guard nsError.code != 201 else {
                self.deliver(result: .failure(NFCManagerError.cancelled), alertMessage: nil)
                return
            }

            self.deliver(result: .failure(error), alertMessage: nil)
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else { return }

        if tags.count > 1 {
            session.alertMessage = NFCManagerError.multipleTags.localizedDescription
            session.restartPolling()
            return
        }

        session.connect(to: firstTag) { error in
            if let error {
                self.fail(error, session: session)
                return
            }

            guard let ndefTag = Self.ndefTag(for: firstTag) else {
                self.fail(
                    NFCManagerError.unsupportedTag,
                    session: session,
                    message: NFCManagerError.unsupportedTag.localizedDescription
                )
                return
            }

            let uidHex = Self.identifierHex(for: firstTag)
            let sessionBox = SendableBox(value: session)
            let ndefTagBox = SendableBox(value: ndefTag)

            switch self.operation {
            case .scanInvocation(_, let rewriteHandler, _):
                ndefTagBox.value.readNDEF { message, error in
                    if let error {
                        self.fail(error, session: sessionBox.value)
                        return
                    }

                    guard let message else {
                        self.fail(
                            NFCManagerError.emptyMessage,
                            session: sessionBox.value,
                            message: NFCManagerError.emptyMessage.localizedDescription
                        )
                        return
                    }

                    let payload = Self.readPayload(from: message, uidHex: uidHex)
                    guard let rewriteHandler else {
                        self.finishReadSuccess(
                            payload: payload,
                            session: sessionBox.value,
                            alertMessage: "标签读取成功"
                        )
                        return
                    }

                    Task { @MainActor in
                        let writeRequest = rewriteHandler(payload)
                        guard let writeRequest else {
                            self.finishReadSuccess(
                                payload: payload,
                                session: sessionBox.value,
                                alertMessage: "标签读取成功"
                            )
                            return
                        }

                        self.performWrite(
                            request: writeRequest,
                            uidHex: uidHex,
                            ndefTag: ndefTagBox.value,
                            session: sessionBox.value,
                            basePayload: payload,
                            degradeFailureToWarning: true
                        )
                    }
                }

            case .readRaw:
                ndefTagBox.value.readNDEF { message, error in
                    if let error {
                        self.fail(error, session: sessionBox.value)
                        return
                    }

                    guard let message else {
                        self.fail(
                            NFCManagerError.emptyMessage,
                            session: sessionBox.value,
                            message: NFCManagerError.emptyMessage.localizedDescription
                        )
                        return
                    }

                    let payload = Self.readPayload(from: message, uidHex: uidHex)
                    self.finishReadSuccess(
                        payload: payload,
                        session: sessionBox.value,
                        alertMessage: "标签读取成功"
                    )
                }

            case .writeURL(_, let url, let snapshot, _):
                self.performWrite(
                    request: NFCNDEFWriteRequest(
                        url: url,
                        snapshot: snapshot,
                        successMessage: "NFC 标签写入成功"
                    ),
                    uidHex: uidHex,
                    ndefTag: ndefTagBox.value,
                    session: sessionBox.value,
                    basePayload: nil,
                    degradeFailureToWarning: false
                )

            case nil:
                session.invalidate()
            }
        }
    }
}
