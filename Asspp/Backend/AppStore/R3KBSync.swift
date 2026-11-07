import Foundation

// Experimental bridge to ipatool's pinned, on-device KBSync generator.
// Account identifiers, generated blobs and raw Go errors must never enter logs.
@_silgen_name("R3GenerateKBSync")
private func R3GenerateKBSync(_ guid: UnsafePointer<CChar>?, _ dsid: UInt64) -> UnsafeMutablePointer<CChar>?

@_silgen_name("R3FreeKBSyncString")
private func R3FreeKBSyncString(_ pointer: UnsafeMutablePointer<CChar>?)

enum R3KBSync {
    struct Generation: Sendable {
        let blob: String?
        /// Constant stage only; safe for in-app diagnostics.
        let status: String
    }

    static func generate(guid: String, directoryServicesIdentifier: String) -> Generation {
        let identifier = directoryServicesIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard guid.utf8.count == 12,
              guid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return Generation(blob: nil, status: "invalid-guid") }

        guard let dsid = UInt64(identifier), dsid != 0
        else { return Generation(blob: nil, status: "invalid-dsid") }

        let pointer = guid.withCString { R3GenerateKBSync($0, dsid) }
        guard let pointer else { return Generation(blob: nil, status: "bridge-unavailable") }
        defer { R3FreeKBSyncString(pointer) }

        let value = String(cString: pointer)
        let knownFailures: Set<String> = [
            "input", "assets", "assets-timeout", "storeagent",
            "storeagent-asset", "storeagent-runtime", "storeagent-init",
            "storeagent-execute", "unicorn-unlinked", "unicorn-runtime",
            "guest", "guest-timeout", "empty",
        ]
        if value.hasPrefix("!R3:") {
            let reason = String(value.dropFirst(4))
            return Generation(blob: nil, status: knownFailures.contains(reason) ? reason : "bridge-error")
        }
        guard !value.isEmpty,
              let data = Data(base64Encoded: value), !data.isEmpty
        else { return Generation(blob: nil, status: "invalid-blob") }

        return Generation(blob: value, status: "ready")
    }
}
