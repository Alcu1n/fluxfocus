//
//  NFCManager.swift
//  fluxfocus
//
//  Created by Codex on 2026/3/12.
//

@preconcurrency import CoreNFC
import Combine
import Foundation

struct NFCScanPayload {
    let uidHex: String
    let url: URL?
    let rawRecords: [String]
}

enum NFCManagerError: LocalizedError {
    case unavailable
    case busy
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
        case .multipleTags: "请一次只贴近一张 NFC 标签。"
        case .unsupportedTag: "检测到的标签不支持 NDEF 读写。"
        case .emptyMessage: "标签中没有可读取的 NDEF 内容。"
        case .invalidURL: "标签中的 URL 无法解析。"
        case .readOnly: "该标签是只读状态，无法写入。"
        case .notWritable: "该标签当前不可写入。"
        case .payloadTooLarge: "写入内容超过标签容量。"
        }
    }
}

final class NFCManager: NSObject, ObservableObject {
    @Published var statusMessage = "待机"
    @Published var lastPayloadSummary = ""

    private var session: NFCTagReaderSession?
    private var operation: Operation?

    private enum Operation {
        case scanInvocation((Result<NFCScanPayload, Error>) -> Void)
        case readRaw((Result<NFCScanPayload, Error>) -> Void)
        case writeURL(URL, (Result<NFCScanPayload, Error>) -> Void)
    }

    private struct SendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    func beginInvocationScan(completion: @escaping (Result<NFCScanPayload, Error>) -> Void) {
        startSession(
            prompt: "将 iPhone 顶部靠近已写入的 FluxFocus NFC 标签",
            operation: .scanInvocation(completion)
        )
    }

    func beginRawRead(completion: @escaping (Result<NFCScanPayload, Error>) -> Void) {
        startSession(
            prompt: "将 iPhone 顶部靠近 NFC 标签以读取内容",
            operation: .readRaw(completion)
        )
    }

    func beginWrite(url: URL, completion: @escaping (Result<NFCScanPayload, Error>) -> Void) {
        startSession(
            prompt: "将空白或可写的 NFC 标签贴近 iPhone 进行写入",
            operation: .writeURL(url, completion)
        )
    }

    private func startSession(prompt: String, operation: Operation) {
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
        statusMessage = prompt

        guard let readerSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self
        ) else {
            statusMessage = NFCManagerError.unavailable.localizedDescription
            deliver(result: .failure(NFCManagerError.unavailable), alertMessage: nil)
            return
        }
        readerSession.alertMessage = prompt
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

        switch result {
        case .success(let payload):
            lastPayloadSummary = payload.rawRecords.joined(separator: "\n")
            statusMessage = "最近一次标签 UID: \(payload.uidHex)"
        case .failure(let error):
            statusMessage = error.localizedDescription
        }

        switch currentOperation {
        case .scanInvocation(let completion):
            completion(result)
        case .readRaw(let completion):
            completion(result)
        case .writeURL(_, let completion):
            completion(result)
        case nil:
            break
        }
    }

    private static func readPayload(from message: NFCNDEFMessage, uidHex: String) -> NFCScanPayload {
        var url: URL?
        var summaries: [String] = []

        for record in message.records {
            if let recordURL = record.wellKnownTypeURIPayload() {
                url = recordURL
                summaries.append(recordURL.absoluteString)
                continue
            }

            let textPayload = record.wellKnownTypeTextPayload()
            if let text = textPayload.0 {
                summaries.append(text)
                continue
            }

            summaries.append("TNF=\(record.typeNameFormat.rawValue), \(record.payload.count) bytes")
        }

        return NFCScanPayload(uidHex: uidHex, url: url, rawRecords: summaries)
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
            defer {
                self.session = nil
                self.operation = nil
            }

            let nsError = error as NSError
            guard nsError.code != 201 else {
                self.statusMessage = "已取消 NFC 会话"
                return
            }

            self.statusMessage = error.localizedDescription
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
                session.invalidate(errorMessage: error.localizedDescription)
                DispatchQueue.main.async {
                    self.deliver(result: .failure(error), alertMessage: nil)
                }
                return
            }

            guard let ndefTag = Self.ndefTag(for: firstTag) else {
                session.invalidate(errorMessage: NFCManagerError.unsupportedTag.localizedDescription)
                DispatchQueue.main.async {
                    self.deliver(result: .failure(NFCManagerError.unsupportedTag), alertMessage: nil)
                }
                return
            }

            let uidHex = Self.identifierHex(for: firstTag)
            let sessionBox = SendableBox(value: session)
            let ndefTagBox = SendableBox(value: ndefTag)

            switch self.operation {
            case .scanInvocation, .readRaw:
                ndefTagBox.value.readNDEF { message, error in
                    if let error {
                        sessionBox.value.invalidate(errorMessage: error.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(error), alertMessage: nil)
                        }
                        return
                    }

                    guard let message else {
                        sessionBox.value.invalidate(errorMessage: NFCManagerError.emptyMessage.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(NFCManagerError.emptyMessage), alertMessage: nil)
                        }
                        return
                    }

                    let payload = Self.readPayload(from: message, uidHex: uidHex)
                    sessionBox.value.alertMessage = "标签读取成功"
                    sessionBox.value.invalidate()
                    DispatchQueue.main.async {
                        self.deliver(result: .success(payload), alertMessage: "标签读取成功")
                    }
                }

            case .writeURL(let url, _):
                ndefTagBox.value.queryNDEFStatus { status, capacity, error in
                    if let error {
                        sessionBox.value.invalidate(errorMessage: error.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(error), alertMessage: nil)
                        }
                        return
                    }

                    guard status != .readOnly else {
                        sessionBox.value.invalidate(errorMessage: NFCManagerError.readOnly.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(NFCManagerError.readOnly), alertMessage: nil)
                        }
                        return
                    }

                    guard status == .readWrite else {
                        sessionBox.value.invalidate(errorMessage: NFCManagerError.notWritable.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(NFCManagerError.notWritable), alertMessage: nil)
                        }
                        return
                    }

                    guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                        sessionBox.value.invalidate(errorMessage: NFCManagerError.invalidURL.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(NFCManagerError.invalidURL), alertMessage: nil)
                        }
                        return
                    }

                    let message = NFCNDEFMessage(records: [payload])
                    let size = payload.payload.count + payload.identifier.count + payload.type.count
                    guard size <= capacity else {
                        sessionBox.value.invalidate(errorMessage: NFCManagerError.payloadTooLarge.localizedDescription)
                        DispatchQueue.main.async {
                            self.deliver(result: .failure(NFCManagerError.payloadTooLarge), alertMessage: nil)
                        }
                        return
                    }

                    ndefTagBox.value.writeNDEF(message) { error in
                        if let error {
                            sessionBox.value.invalidate(errorMessage: error.localizedDescription)
                            DispatchQueue.main.async {
                                self.deliver(result: .failure(error), alertMessage: nil)
                            }
                            return
                        }

                        let result = NFCScanPayload(
                            uidHex: uidHex,
                            url: url,
                            rawRecords: [url.absoluteString]
                        )
                        sessionBox.value.alertMessage = "NFC 标签写入成功"
                        sessionBox.value.invalidate()
                        DispatchQueue.main.async {
                            self.deliver(result: .success(result), alertMessage: "NFC 标签写入成功")
                        }
                    }
                }

            case nil:
                session.invalidate()
            }
        }
    }
}
