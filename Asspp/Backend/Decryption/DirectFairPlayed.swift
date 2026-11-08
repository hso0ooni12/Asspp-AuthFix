#if os(iOS)
import CryptoKit
import Darwin
import Foundation
import ZIPFoundation

/// R19 is an on-device experiment, not a claim that iOS permits downloaded
/// payloads to be decrypted from Asspp's data container.
struct DirectDecryptionRequest: Sendable {
    let input: URL
    let bundleID: String
    let name: String
    let version: String
    let outputDirectory: URL
}

struct DirectDecryptionOutcome: Sendable {
    let output: URL?
    let report: URL?
    let message: String
}

private enum NativeFairPlayed {
    typealias Inspect = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>, Int) -> Int32
    typealias Process = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafeMutablePointer<CChar>, Int) -> Int32
    typealias Resolve = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>, Int) -> Int32

    static func symbol<T>(_ name: String, as: T.Type) throws -> T {
        guard let handle = dlopen(nil, RTLD_NOW) else { throw DirectError.engineMissing }
        defer { dlclose(handle) }
        guard let address = dlsym(handle, name) else { throw DirectError.engineMissing }
        return unsafeBitCast(address, to: T.self)
    }

    static func inspect(_ file: URL) throws -> (Int32, String) {
        let function = try symbol("AssppFPInspect", as: Inspect.self)
        var text = [CChar](repeating: 0, count: 65536)
        let capacity = text.count
        let code = file.path.withCString { function($0, &text, capacity) }
        return (code, String(cString: text))
    }

    static func process(source: URL, output: URL) throws -> (Int32, String) {
        let function = try symbol("AssppFPProcess", as: Process.self)
        var text = [CChar](repeating: 0, count: 65536)
        let capacity = text.count
        let code = source.path.withCString { sourcePath in
            output.path.withCString { function(sourcePath, $0, &text, capacity) }
        }
        return (code, String(cString: text))
    }

    static func installedBundle(_ bundleID: String) throws -> URL? {
        let function = try symbol("AssppFPResolveInstalled", as: Resolve.self)
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        let capacity = path.count
        let code = bundleID.withCString { function($0, &path, capacity) }
        guard code == 0 else { return nil }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
}

private enum DirectError: LocalizedError {
    case engineMissing, unsafeArchive, invalidIPA, bundleMismatch, unsupportedBinary
    case decryptionRejected, finalVerification, storage

    var errorDescription: String? {
        switch self {
        case .engineMissing: "The experimental FairPlayed engine is missing from this build."
        case .unsafeArchive: "The IPA contains unsupported paths, links or archive sizes."
        case .invalidIPA: "The IPA must contain one complete iOS app."
        case .bundleMismatch: "The IPA does not match the selected app."
        case .unsupportedBinary: "A binary failed validation or exceeds this experiment's limits."
        case .decryptionRejected: "Direct decryption was not accepted. No IPA was exported. Share the diagnostic report to identify the failed stage."
        case .finalVerification: "Final verification failed. No IPA was exported."
        case .storage: "There is not enough free space for extraction and IPA export."
        }
    }
}

private final class DirectDiagnostic {
    private var lines: [String] = []
    private var bytes = 0
    func add(_ text: String) {
        // Native messages contain relative names, errno and page results only.
        // Never record private absolute paths, licenses, account IDs or tokens.
        guard bytes < 256 * 1024 else { return }
        let bounded = String(text.prefix(8192))
        lines.append(bounded)
        bytes += bounded.utf8.count
    }
    func save(to url: URL, conclusion: String) throws {
        try (lines.joined(separator: "\n") + "\n\nRESULT: " + conclusion + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}

enum DirectFairPlayed {
    private static let fm = FileManager.default

    static func run(_ request: DirectDecryptionRequest,
                    progress: @Sendable (String) -> Void) -> DirectDecryptionOutcome {
        let id = UUID().uuidString
        let report = request.outputDirectory.appendingPathComponent("Reports/Direct-\(id).txt")
        let work = fm.temporaryDirectory.appendingPathComponent("Asspp-Direct-\(id)", isDirectory: true)
        let package = work.appendingPathComponent("Package", isDirectory: true)
        let log = DirectDiagnostic()
        var candidate: URL?
        defer {
            try? fm.removeItem(at: work)
            if let candidate { try? fm.removeItem(at: candidate) }
        }
        func checkpoint(_ stage: String) {
            log.add(stage)
            try? log.save(to: report, conclusion: "IN PROGRESS: \(stage)")
            progress(stage)
        }
        do {
            try fm.createDirectory(at: report.deletingLastPathComponent(), withIntermediateDirectories: true)
            log.add("Asspp R21 · Direct FairPlayed four-mode experiment · not device-validated by CI")
            log.add("Core: morzelowski/FairPlayed bad7df138839b5e0ac8b9f20cc4689140b8436fb + R9 tiny-stub check")
            log.add("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            log.add("Modes: R/cryptid2 + RX/cryptid1 (four upstream attempts); no code execution or JIT")
            log.add("Private account and license data are omitted.")
            // Fail early on builds that did not link the experimental engine.
            let _: NativeFairPlayed.Process = try NativeFairPlayed.symbol("AssppFPProcess", as: NativeFairPlayed.Process.self)
            checkpoint("Checking the downloaded IPA...")
            try validateArchive(request.input, outputDirectory: request.outputDirectory)
            try fm.unzipItem(at: request.input, to: package)
            let payload = package.appendingPathComponent("Payload", isDirectory: true)
            let payloadItems = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey])
            guard payloadItems.count == 1, let app = payloadItems.first,
                  app.pathExtension.lowercased() == "app",
                  try app.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw DirectError.invalidIPA }
            // Export only Payload, as the working helper does. Do not carry
            // purchase/account metadata or arbitrary root files into the result.
            for item in try fm.contentsOfDirectory(at: package, includingPropertiesForKeys: nil) where item != payload {
                try fm.removeItem(at: item)
            }
            let downloadedInfo = try info(app)
            guard downloadedInfo["CFBundleIdentifier"] as? String == request.bundleID else { throw DirectError.bundleMismatch }
            guard let executable = downloadedInfo["CFBundleExecutable"] as? String,
                  safeRelativePath(executable), !executable.contains("/"),
                  fm.fileExists(atPath: app.appendingPathComponent(executable).path) else { throw DirectError.invalidIPA }
            // Same iPhone-only export scope as the working FairPlayed helper.
            let watch = app.appendingPathComponent("Watch", isDirectory: true)
            if fm.fileExists(atPath: watch.path) {
                try fm.removeItem(at: watch)
                log.add("Watch companion excluded (iPhone-only export).")
            }
            let binaries = try machoFiles(in: app)
            guard binaries.contains(app.appendingPathComponent(executable)) else { throw DirectError.invalidIPA }
            var encrypted: [URL] = []
            for file in binaries {
                let (state, note) = try NativeFairPlayed.inspect(file)
                if !note.isEmpty { log.add("\(relative(file, to: app)): \(note)") }
                guard state >= 0 else { throw DirectError.unsupportedBinary }
                if state == 1 { encrypted.append(file) }
            }
            log.add("Mach-O files: \(binaries.count); encrypted: \(encrypted.count).")
            let installed = try matchingInstalledBundle(request.bundleID, downloaded: downloadedInfo, log: log)
            if !encrypted.isEmpty {
                // Reproduce missing sibling SINF copies in our disposable stage.
                // This does not grant fairplayd access to Asspp's data container.
                if fm.fileExists(atPath: app.appendingPathComponent("SC_Info/Manifest.plist").path) {
                    try FairPlayedHelper.normalizeLicenseForDirectAttempt(at: app)
                }
                for (index, binary) in encrypted.enumerated() {
                    let rel = relative(binary, to: app)
                    checkpoint("Decrypting file \(index + 1) of \(encrypted.count)...")
                    log.add("Binary: \(rel)")
                    let temporaryOutput = binary.deletingLastPathComponent()
                        .appendingPathComponent(".Asspp-direct-\(UUID().uuidString)")
                    var succeeded = false
                    if let installed {
                        let source = installed.appendingPathComponent(rel)
                        do {
                            // Never mix another installed version/thinning with
                            // this IPA. Require the complete original binary hash.
                            guard try digest(source) == digest(binary) else {
                                log.add("Installed source: binary differs; skipped.")
                                throw DirectSourceUnavailable()
                            }
                            log.add("Installed source: exact original SHA-256 match; attempting read-only decrypt.")
                            try? log.save(to: report, conclusion: "IN PROGRESS: installed-source remap")
                            let (code, note) = try NativeFairPlayed.process(source: source, output: temporaryOutput)
                            log.add(note)
                            succeeded = code == 0
                        } catch {
                            log.add("Installed source unavailable (\(sanitizedCode(error))).")
                        }
                    }
                    if !succeeded {
                        log.add("Downloaded data-container source: attempting read-only decrypt.")
                        try? log.save(to: report, conclusion: "IN PROGRESS: data-container remap")
                        let (code, note) = try NativeFairPlayed.process(source: binary, output: temporaryOutput)
                        log.add(note)
                        succeeded = code == 0
                    }
                    guard succeeded else { throw DirectError.decryptionRejected }
                    let (verified, _) = try NativeFairPlayed.inspect(temporaryOutput)
                    guard verified == 0 else { throw DirectError.finalVerification }
                    try fm.removeItem(at: binary)
                    try fm.moveItem(at: temporaryOutput, to: binary)
                }
            }
            checkpoint("Verifying all binaries...")
            // Re-scan the complete payload, not merely the main executable.
            for binary in try machoFiles(in: app) {
                let (state, _) = try NativeFairPlayed.inspect(binary)
                guard state == 0 else { throw DirectError.finalVerification }
            }
            try stripObsoleteSignatures(in: app)
            let outputs = request.outputDirectory.appendingPathComponent("Decrypted", isDirectory: true)
            try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
            let output = outputs.appendingPathComponent(safeName(request.name) + "-" + safeName(request.version) + "-decrypted-" + String(id.prefix(8)) + ".ipa")
            candidate = output
            checkpoint("Exporting the verified IPA...")
            try fm.zipItem(at: package, to: output, shouldKeepParent: false, compressionMethod: .deflate)
            // Verify the ZIP CRCs too, before exposing the result to the share UI.
            let archive = try Archive(url: output, accessMode: .read)
            for entry in archive where entry.type == .file {
                let crc = try archive.extract(entry, consumer: { _ in })
                guard crc == entry.checksum else { throw DirectError.finalVerification }
            }
            let conclusion = encrypted.isEmpty ? "ALREADY PLAINTEXT; all Mach-O files checked." : "COMPLETE; every encrypted slice passed FairPlayed checks and final cryptid verification."
            log.add("The exported IPA is unsigned and may require signing for installation.")
            try log.save(to: report, conclusion: conclusion)
            candidate = nil
            return DirectDecryptionOutcome(output: output, report: report, message: encrypted.isEmpty ? "IPA was already decrypted." : "Direct decryption completed.")
        } catch {
            let message = (error as? DirectError)?.localizedDescription
                ?? "Direct decryption stopped (\(sanitizedCode(error))). No IPA was exported."
            log.add("Failure: \(message)")
            try? log.save(to: report, conclusion: "FAILED; no decrypted IPA exported.")
            return DirectDecryptionOutcome(output: nil, report: fm.fileExists(atPath: report.path) ? report : nil, message: message)
        }
    }

    private struct DirectSourceUnavailable: Error {}

    private static func matchingInstalledBundle(_ id: String, downloaded: [String: Any], log: DirectDiagnostic) throws -> URL? {
        guard let installed = try NativeFairPlayed.installedBundle(id) else {
            log.add("Installed lookup: unavailable or denied. No apps were enumerated.")
            return nil
        }
        do {
            let installedInfo = try info(installed)
            for key in ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"] {
                guard let value = downloaded[key] as? String, installedInfo[key] as? String == value else {
                    log.add("Installed source: app/build/version mismatch; skipped."); return nil
                }
            }
            log.add("Installed source: metadata readable and exact version matches.")
            return installed
        } catch {
            log.add("Installed source: metadata unreadable (\(sanitizedCode(error))).")
            return nil
        }
    }

    private static func validateArchive(_ input: URL, outputDirectory: URL) throws {
        let archive = try Archive(url: input, accessMode: .read)
        var total: UInt64 = 0
        var paths: Set<String> = []
        var count = 0
        for entry in archive {
            count += 1
            let normalized = entry.path.precomposedStringWithCanonicalMapping.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard safeRelativePath(entry.path), entry.type != .symlink,
                  paths.insert(normalized).inserted, count <= 100_000 else { throw DirectError.unsafeArchive }
            let size = UInt64(entry.uncompressedSize)
            guard size <= 8 * 1024 * 1024 * 1024, total <= 8 * 1024 * 1024 * 1024 - size else { throw DirectError.unsafeArchive }
            total += size
        }
        let available = try outputDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let available, UInt64(max(0, available)) < total * 3 + 128 * 1024 * 1024 { throw DirectError.storage }
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
            !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
            !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    private static func info(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw DirectError.invalidIPA }
        return result
    }

    private static func machoFiles(in app: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey]
        var traversalError: Error?
        guard let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: keys, errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw DirectError.invalidIPA }
        var files: [URL] = []
        let magic: Set<UInt32> = [0xfeedfacf, 0xfeedface, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw DirectError.unsafeArchive }
            guard values.isRegularFile == true else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            let head: Data
            do { head = try handle.read(upToCount: 4) ?? Data(); try handle.close() }
            catch { try? handle.close(); throw error }
            if head.count == 4 {
                let value = head.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
                if magic.contains(value) { files.append(file) }
            }
        }
        if let traversalError { throw traversalError }
        return files.sorted { $0.path < $1.path }
    }

    private static func digest(_ file: URL) throws -> SHA256.Digest {
        // Reject redirections even if a resolver returns an unexpected path.
        let canonical = file.resolvingSymlinksInPath().standardizedFileURL
        // /var and /private/var are the same on iOS; compare via parent resolution.
        let parent = file.deletingLastPathComponent().resolvingSymlinksInPath()
        guard canonical == parent.appendingPathComponent(file.lastPathComponent).standardizedFileURL else { throw DirectSourceUnavailable() }
        let handle = try FileHandle(forReadingFrom: canonical)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hasher.update(data: bytes) }
        return hasher.finalize()
    }

    private static func stripObsoleteSignatures(in app: URL) throws {
        var obsolete: [URL] = []
        guard let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: nil) else { throw DirectError.invalidIPA }
        for case let file as URL in enumerator {
            if ["SC_Info", "_CodeSignature", "embedded.mobileprovision"].contains(file.lastPathComponent) {
                obsolete.append(file); enumerator.skipDescendants()
            }
        }
        for file in obsolete { try fm.removeItem(at: file) }
    }

    private static func relative(_ file: URL, to root: URL) -> String {
        String(file.path.dropFirst(root.path.count + 1))
    }
    private static func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return String((cleaned.isEmpty ? "App" : cleaned).prefix(64))
    }
    private static func sanitizedCode(_ error: Error) -> String {
        // No NSError userInfo/localizedDescription: those can contain full paths.
        "\((error as NSError).domain) code \((error as NSError).code)"
    }
}
#endif
