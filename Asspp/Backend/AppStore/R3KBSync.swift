import Foundation

// Experimental bridge to the open-source ipatool KBSync generator.
// Never log the blob, Apple account tokens, or a package's signed URL.
@_silgen_name("R3GenerateKBSync")
private func R3GenerateKBSync(_ guid: UnsafePointer<CChar>?, _ dsid: UInt64) -> UnsafeMutablePointer<CChar>?

@_silgen_name("R3FreeKBSyncString")
private func R3FreeKBSyncString(_ pointer: UnsafeMutablePointer<CChar>?)

enum R3KBSync {
    static func generate(guid: String, directoryServicesIdentifier: String) -> String? {
        guard guid.utf8.count == 12,
              guid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let dsid = UInt64(directoryServicesIdentifier), dsid != 0
        else { return nil }
        let pointer = guid.withCString { R3GenerateKBSync($0, dsid) }
        guard let pointer else { return nil }
        defer { R3FreeKBSyncString(pointer) }
        let value = String(cString: pointer)
        guard !value.isEmpty, Data(base64Encoded: value) != nil else { return nil }
        return value
    }
}
