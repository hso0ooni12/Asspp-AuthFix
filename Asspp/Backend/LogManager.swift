//
//  LogManager.swift
//  Asspp
//
//  Created on 2026/2/20.
//

import Foundation
import Logging

final nonisolated class LogManager: Sendable {
    static let shared = LogManager()

    private static let maxMessages = 2000

    private let messageQueue = DispatchQueue(label: "wiki.qaq.log")
    // Confined to messageQueue, so a single formatter instance is safe to reuse.
    private nonisolated(unsafe) let timestampFormatter = ISO8601DateFormatter()
    private nonisolated(unsafe) var messages: [String] = []

    func write(_ content: String) {
        messageQueue.async {
            let timestamp = self.timestampFormatter.string(from: Date())
            let logMessage = "[\(timestamp)]\n\(content)"
            self.messages.append(logMessage)
            // Cap retained history so a long-running session cannot grow memory
            // without bound.
            if self.messages.count > Self.maxMessages {
                self.messages.removeFirst(self.messages.count - Self.maxMessages)
            }
        }
    }

    func getMessages() -> [String] {
        messageQueue.sync { messages }
    }
}

struct LogManagerHandler: LogHandler {
    var logLevel: Logger.Level = .debug
    var metadata: Logger.Metadata = [:]
    let label: String

    /// Every log destination shares this basic redaction boundary. Stage codes
    /// remain visible, while email addresses and common credential fields do not.
    private static func sanitized(_ message: String) -> String {
        message
            .replacingOccurrences(
                of: #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                with: "[account]", options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\b(password|x-token|cookie|authorization|kbsync|dsid|guid)\b\s*[:=]\s*[^,\s]+"#,
                with: "$1=[redacted]", options: .regularExpression
            )
            .replacingOccurrences(
                of: #"https?://[^\s]+"#,
                with: "[network URL]", options: .regularExpression
            )
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata _: Logger.Metadata?,
        source _: String,
        file _: String,
        function _: String,
        line _: UInt,
    ) {
        let text = Self.sanitized("[\(level)] [\(label)] \(message)")
        Swift.print(text)
        LogManager.shared.write(text)
    }
}
