//
//  PackageView.swift
//  Velo — App Store-style download details
//

import ApplePackage
import ButtonKit
import Kingfisher
import SwiftUI
#if os(iOS)
import ZIPFoundation
import Security
#endif

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
#endif

struct PackageView: View {
    @State var pkg: PackageManifest

    var archive: AppStore.AppPackage { pkg.package }
    var url: URL { pkg.targetLocation }

    @Environment(\.dismiss) var dismiss
    #if os(iOS)
        @State private var installer: Installer?
        @State private var error: String = ""
        @State private var decryptor = DecryptionCenter.shared
    #endif
    #if os(macOS)
        @State private var copied = false
    #endif

    @State private var vm = AppStore.this
    @State private var downloads = Downloads.this

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero
                if pkg.completed {
                    completedActions
                } else {
                    transferActions
                }
                packageInformation
                accountInformation
                advancedTools
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 30)
        }
        .background(AssppTheme.background)
        .tint(AssppTheme.accent)
        .navigationTitle("Download Details")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            KFImage(URL(string: archive.software.artworkUrl))
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 100, height: 100)))
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 23))
            VStack(alignment: .leading, spacing: 6) {
                Text(archive.software.name)
                    .font(.title2.bold())
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(archive.software.sellerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Version \(archive.software.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var completedActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Ready to Decrypt")
            #if os(iOS)
                Button {
                    decryptor.prepare(pkg)
                } label: {
                    Label(decryptor.status(for: pkg) == .preparing
                          ? "Preparing FairPlayed..." : "Decrypt IPA",
                          systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VeloPillButtonStyle(prominent: true))
                .disabled(decryptor.status(for: pkg) == .preparing)

                switch decryptor.status(for: pkg) {
                case .preparing:
                    ProgressView("Preparing FairPlayed...")
                case .ready:
                    Button {
                        decryptor.shareExisting(pkg)
                    } label: {
                        Label("Share Prepared IPA", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(VeloPillButtonStyle())
                case let .failed(message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                case .idle:
                    EmptyView()
                }
                Text("Velo prepares a FairPlayed helper. Sign it with your signing app, then open it to export the decrypted IPA.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Installation options") {
                    VStack(alignment: .leading, spacing: 12) {
                        AsyncButton {
                            installer = try await Installer(archive: archive, path: url)
                        } label: {
                            Label("Install", systemImage: "square.and.arrow.down")
                        }
                        .disabledWhenLoading()
                        .sheet(item: $installer) {
                            installer?.destroy()
                            installer = nil
                        } content: {
                            InstallerView(installer: $0)
                        }
                        Button {
                            let newURL = temporaryDirectory
                                .appendingPathComponent("\(archive.software.bundleID)-\(archive.software.version)")
                                .appendingPathExtension("ipa")
                            try? FileManager.default.removeItem(at: newURL)
                            try? FileManager.default.copyItem(at: url, to: newURL)
                            AirDrop(items: [newURL])
                        } label: {
                            Label("Install via AirDrop", systemImage: "airplayaudio")
                        }
                        if !error.isEmpty {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 9)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #else
                DeviceCTLInstallSection(package: pkg)
            #endif
        }
    }

    private var transferActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Download")
            HStack(spacing: 10) {
                Text(pkg.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Text("\(Int(pkg.state.percent * 100))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            ProgressView(value: pkg.state.percent)
                .tint(AssppTheme.accent)
            HStack(spacing: 10) {
                ForEach(downloads.getAvailableActions(for: pkg).filter { $0 != .delete }, id: \.self) { action in
                    let label = downloads.getActionLabel(for: action)
                    Button {
                        downloads.performDownloadAction(for: pkg, action: action)
                    } label: {
                        Label(label.title, systemImage: label.systemImage)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                }
            }
            if let error = pkg.state.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
    }

    private var packageInformation: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Information")
            VStack(spacing: 0) {
                detailRow("Bundle ID", archive.software.bundleID)
                Divider()
                detailRow("Version", archive.software.version)
                Divider()
                detailRow("Developer", archive.software.sellerName)
                if !archive.software.primaryGenreName.isEmpty {
                    Divider()
                    detailRow("Category", archive.software.primaryGenreName)
                }
                Divider()
                detailRow("Requires", "iOS \(archive.software.minimumOsVersion)+")
                if archive.software.userRatingCount > 0 {
                    Divider()
                    detailRow("Rating", String(format: "%.1f", archive.software.averageUserRating))
                }
            }
            .padding(.horizontal, 14)
            .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private var accountInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Account")
            Text(pkg.account.account.email)
                .font(.subheadline)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            Text("\(pkg.account.account.store) · \(ApplePackage.Configuration.countryCode(for: pkg.account.account.store) ?? String(localized: "Unknown"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("More")
            NavigationLink {
                FileListView(packageURL: pkg.targetLocation)
            } label: {
                Label("Browse IPA Contents", systemImage: "folder")
                    .font(.subheadline.weight(.medium))
            }
            #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            #endif
            Divider()
            Button(role: .destructive) {
                dismiss()
                Task { @MainActor in
                    await Task.yield()
                    downloads.performDownloadAction(for: pkg, action: .delete)
                }
            } label: {
                Label("Delete Download", systemImage: "trash")
                    .font(.subheadline)
            }
        }
        .padding(.top, 5)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: 86, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 13)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold())
    }
}

#if os(iOS)
struct PreparedDecryptionPackage: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct AssppActivityShare: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum DecryptionPreparationStatus: Equatable {
    case idle, preparing, ready, failed(String)
}

/// Shared, main-actor coordination prevents duplicate helper exports from the
/// detail view, context menu, swipe actions and automatic post-download flow.
@MainActor
@Observable
final class DecryptionCenter {
    static let shared = DecryptionCenter()

    var statuses: [UUID: DecryptionPreparationStatus] = [:]
    var sharePackage: PreparedDecryptionPackage?
    var isPreparingBatch = false
    var batchCompleted = 0
    var batchTotal = 0
    var batchError: String?

    @ObservationIgnored private var running: Set<UUID> = []

    private init() {
        RetiredSigningCleanup.run()
    }

    func status(for manifest: PackageManifest) -> DecryptionPreparationStatus {
        if let stored = statuses[manifest.id] { return stored }
        guard preparedURL(for: manifest) != nil else { return .idle }
        return .ready
    }

    func preparedURL(for manifest: PackageManifest) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key(for: manifest)) else { return nil }
        let file = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func shareExisting(_ manifest: PackageManifest) {
        guard let file = preparedURL(for: manifest) else {
            statuses[manifest.id] = .failed("Prepared IPA not found. Please prepare it again.")
            return
        }
        sharePackage = PreparedDecryptionPackage(url: file)
    }

    func prepare(_ manifest: PackageManifest) {
        guard manifest.completed, !isPreparingBatch, running.insert(manifest.id).inserted else { return }
        statuses[manifest.id] = .preparing
        let input = manifest.targetLocation
        let bundleID = manifest.package.software.bundleID
        let appName = manifest.package.software.name
        let appVersion = manifest.package.software.version
        let storageKey = key(for: manifest)
        let id = manifest.id

        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try FairPlayedHelper.prepare(
                        downloadedIPA: input,
                        expectedBundleID: bundleID,
                        name: appName,
                        version: appVersion
                    )
                }.value
                // Keep a single prepared helper per download, but never touch
                // anything the user has already saved outside Asspp's folder.
                if let previous = UserDefaults.standard.string(forKey: storageKey),
                   previous != output.path,
                   URL(fileURLWithPath: previous).deletingLastPathComponent() ==
                       documentsDirectory.appendingPathComponent("FairPlayed/Prepared", isDirectory: true) {
                    try? FileManager.default.removeItem(atPath: previous)
                }
                UserDefaults.standard.set(output.path, forKey: storageKey)
                statuses[id] = .ready
                sharePackage = PreparedDecryptionPackage(url: output)
            } catch {
                statuses[id] = .failed(error.localizedDescription)
            }
            running.remove(id)
        }
    }

    /// One signed FairPlayed helper can hold several complete app bundles.
    /// When launched, its embedded export loops over every app and shares a ZIP
    /// only if all Mach-O components in every app decrypted and verified.
    func prepareBatch(_ manifests: [PackageManifest]) {
        let selected = manifests.filter(\.completed)
        guard !selected.isEmpty, !isPreparingBatch else { return }
        guard !selected.contains(where: { running.contains($0.id) }) else {
            batchError = "Wait for the individual app preparation to finish, then retry the batch."
            return
        }
        if selected.count == 1 {
            prepare(selected[0])
            return
        }
        isPreparingBatch = true
        batchCompleted = 0
        batchTotal = selected.count
        batchError = nil
        let inputs = selected.map { manifest in
            statuses[manifest.id] = .preparing
            return FairPlayedBatchArchive.Input(
                id: manifest.id,
                downloadedIPA: manifest.targetLocation,
                bundleID: manifest.package.software.bundleID,
                name: manifest.package.software.name,
                version: manifest.package.software.version
            )
        }
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FairPlayedBatchArchive.create(inputs: inputs) { finished in
                        Task { @MainActor in
                            DecryptionCenter.shared.batchCompleted = finished
                        }
                    }
                }.value
                for input in inputs { statuses.removeValue(forKey: input.id) }
                batchCompleted = batchTotal
                sharePackage = PreparedDecryptionPackage(url: result)
            } catch {
                batchError = error.localizedDescription
                // A bulk packaging error is not an error in every downloaded
                // app. Keep their individual "Decrypt IPA" actions usable.
                for input in inputs { statuses.removeValue(forKey: input.id) }
            }
            isPreparingBatch = false
        }
    }

    private func key(for manifest: PackageManifest) -> String {
        "Asspp.PreparedFairPlayed.\(manifest.id.uuidString)"
    }

    var preparedStorageSize: Int64 {
        let dir = documentsDirectory.appendingPathComponent("FairPlayed/Prepared", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let signedDir = documentsDirectory.appendingPathComponent("FairPlayed/Signed", isDirectory: true)
        let signed = (try? FileManager.default.contentsOfDirectory(at: signedDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let exportsDir = documentsDirectory.appendingPathComponent("FairPlayed/Exports", isDirectory: true)
        let exports = (try? FileManager.default.contentsOfDirectory(at: exportsDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return (files + signed + exports).reduce(0) { sum, file in
            sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearPreparedHelpers() {
        guard !isPreparingBatch, running.isEmpty else { return }
        for name in ["Prepared", "Signed", "Exports"] {
            let dir = documentsDirectory.appendingPathComponent("FairPlayed/\(name)", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where ["ipa", "zip"].contains(file.pathExtension.lowercased()) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix("Asspp.PreparedFairPlayed.") || key.hasPrefix("Asspp.SignedFairPlayed.") {
            defaults.removeObject(forKey: key)
        }
        statuses.removeAll()
        sharePackage = nil
    }
}

/// Value-only inputs cross the detached task boundary without sharing live
/// @Observable PackageManifest state.
fileprivate enum FairPlayedBatchArchive {
    struct Input: Sendable {
        let id: UUID
        let downloadedIPA: URL
        let bundleID: String
        let name: String
        let version: String
    }

    static func create(inputs: [Input], progress: @escaping @Sendable (Int) -> Void) throws -> URL {
        try FairPlayedHelper.prepareBatch(inputs: inputs, progress: progress)
    }
}

/// Removes only the obsolete in-app signer's three records. It never reads or
/// modifies App Store account tokens, the installed app's signature, or source files.
private enum RetiredSigningCleanup {
    static func run() {
        let defaults = UserDefaults.standard
        let migrationKey = "Asspp.R17.RetiredSignerCleaned"
        guard !defaults.bool(forKey: migrationKey) else { return }
        var allRemoved = true
        for account in ["p12", "mobileprovision", "p12-password"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "wiki.qaq.Asspp.AuthFix.R12Signer",
                kSecAttrAccount as String: account,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                allRemoved = false
            }
        }
        // Ignore old signed-helper cache pointers without deleting user IPAs.
        for (key, value) in defaults.dictionaryRepresentation() {
            if key.hasPrefix("Asspp.SignedFairPlayed.") {
                defaults.removeObject(forKey: key)
            } else if key.hasPrefix("Asspp.PreparedFairPlayed."),
                      let path = value as? String,
                      URL(fileURLWithPath: path).deletingLastPathComponent() ==
                          documentsDirectory.appendingPathComponent("FairPlayed/Signed", isDirectory: true) {
                defaults.removeObject(forKey: key)
            }
        }
        if allRemoved { defaults.set(true, forKey: migrationKey) }
    }
}

/// CI bundles the pinned, empty FairPlayed shell with Asspp. No user file picker.
enum FairPlayedHelper {
    private static let fm = FileManager.default
    private static var base: URL {
        documentsDirectory.appendingPathComponent("FairPlayed", isDirectory: true)
    }

    /// Imported IPA files use the same checked FairPlayed packaging pipeline
    /// as Store downloads. Importing does not bypass FairPlay entitlements or
    /// decrypt code by itself; the separate signed helper performs that on device.
    static func prepareImportedIPA(_ imported: URL) throws -> URL {
        guard imported.pathExtension.lowercased() == "ipa" else {
            throw PreparationError.notIPA
        }
        let archive = try Archive(url: imported, accessMode: .read)
        // Imported IPA files are untrusted. Limit expanded size and check free
        // space before ZIPFoundation extracts or duplicates any application.
        let expandedLimit: UInt64 = 6 * 1024 * 1024 * 1024
        var expandedSize: UInt64 = 0
        for entry in archive {
            let size = UInt64(entry.uncompressedSize)
            guard size <= expandedLimit, expandedSize <= expandedLimit - size else {
                throw PreparationError.unsafeArchive
            }
            expandedSize += size
        }
        let requiredBytes = Int64(expandedSize) * 3 + 256 * 1024 * 1024
        if let available = try? documentsDirectory.resourceValues(forKeys:
            [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < requiredBytes {
            throw PreparationError.insufficientSpace(needed: requiredBytes, available: available)
        }
        // Do not unpack untrusted files until the central path-safety check.
        try validateArchive(imported)
        let plistEntries = archive.filter { entry in
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
        guard plistEntries.count == 1, let infoEntry = plistEntries.first,
              infoEntry.uncompressedSize <= 1024 * 1024
        else { throw PreparationError.notIPA }
        var data = Data()
        _ = try archive.extract(infoEntry) { chunk in
            data.append(chunk)
        }
        guard let info = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
              let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty
        else { throw PreparationError.notIPA }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleID
        return try prepare(downloadedIPA: imported, expectedBundleID: bundleID,
                           name: name, version: version)
    }

    static func prepare(downloadedIPA: URL, expectedBundleID: String, name: String, version: String) throws -> URL {
        guard let shell = Bundle.main.url(forResource: "FairPlayed-shell", withExtension: "zip")
        else { throw PreparationError.missingShell }
        guard fm.fileExists(atPath: downloadedIPA.path) else { throw PreparationError.missingDownload }
        let root = fm.temporaryDirectory.appendingPathComponent("FairPlayedBuild-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let staged = root.appendingPathComponent("Staged", isDirectory: true)
        let input = root.appendingPathComponent("Input", isDirectory: true)
        try validateArchive(shell)
        try validateArchive(downloadedIPA)
        try fm.unzipItem(at: shell, to: staged)
        try fm.unzipItem(at: downloadedIPA, to: input)
        let helper = staged.appendingPathComponent("FairPlayed.app", isDirectory: true)
        guard fm.fileExists(atPath: helper.appendingPathComponent("FairPlayed").path),
              (try info(at: helper)["CFBundleExecutable"] as? String) == "FairPlayed"
        else { throw PreparationError.invalidShell }
        try configureHelper(at: helper, targetName: name)
        let target = try findApp(in: input)
        guard (try info(at: target)["CFBundleIdentifier"] as? String) == expectedBundleID else {
            throw PreparationError.bundleMismatch
        }
        let embedded = helper.appendingPathComponent("EmbeddedPayload", isDirectory: true)
        if fm.fileExists(atPath: embedded.path) { try fm.removeItem(at: embedded) }
        try fm.createDirectory(at: embedded, withIntermediateDirectories: true)

        // FairPlayed must be signed with the target inside its own app bundle.
        // Dropping .app on the embedded directory keeps encrypted code as resources.
        let copied = embedded.appendingPathComponent(target.deletingPathExtension().lastPathComponent, isDirectory: true)
        try fm.copyItem(at: target, to: copied)
        let watch = copied.appendingPathComponent("Watch", isDirectory: true)
        if fm.fileExists(atPath: watch.path) { try fm.removeItem(at: watch) }
        try replicateSINF(in: copied)

        let payload = staged.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try fm.moveItem(at: helper, to: payload.appendingPathComponent("FairPlayed.app", isDirectory: true))

        let outputs = base.appendingPathComponent("Prepared", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        let output = outputs.appendingPathComponent(
            safePart(name) + "-" + safePart(version) + "-FairPlayed-" + String(UUID().uuidString.prefix(8)) + ".ipa"
        )
        try fm.zipItem(at: staged, to: output, shouldKeepParent: false, compressionMethod: .deflate)
        let packed = try Archive(url: output, accessMode: .read)
        guard packed.contains(where: { $0.path.contains("/EmbeddedPayload/") }) else {
            try? fm.removeItem(at: output)
            throw PreparationError.emptyPayload
        }
        return output
    }

    /// Batch version of the known-good single-app assembly. The helper itself
    /// contains every selected app as a resource without nested .app suffixes.
    /// FairPlayed's multi-app export then performs all decryptions on-device.
    fileprivate static func prepareBatch(
        inputs: [FairPlayedBatchArchive.Input],
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> URL {
        guard inputs.count > 1,
              let shell = Bundle.main.url(forResource: "FairPlayed-shell", withExtension: "zip")
        else { throw PreparationError.missingShell }
        // Decompression and re-signing use real filesystem space, not only the
        // source IPA's compressed size. Fail before modifying any input files.
        let sourceSize = inputs.reduce(Int64(0)) { sum, entry in
            let size = (try? entry.downloadedIPA.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(max(size, 0))
        }
        let estimatedExtraBytes = min(sourceSize, Int64.max / 4) * 3 + 256 * 1024 * 1024
        if let available = try? documentsDirectory.resourceValues(forKeys:
            [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < estimatedExtraBytes {
            throw PreparationError.insufficientSpace(needed: estimatedExtraBytes, available: available)
        }
        let root = fm.temporaryDirectory.appendingPathComponent("FairPlayedBatch-" + UUID().uuidString,
                                                                  isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let staged = root.appendingPathComponent("Staged", isDirectory: true)
        try validateArchive(shell)
        try fm.unzipItem(at: shell, to: staged)
        let helper = staged.appendingPathComponent("FairPlayed.app", isDirectory: true)
        guard fm.fileExists(atPath: helper.appendingPathComponent("FairPlayed").path),
              (try info(at: helper)["CFBundleExecutable"] as? String) == "FairPlayed"
        else { throw PreparationError.invalidShell }
        try configureHelper(at: helper, targetName: "\(inputs.count) Apps")
        let embedded = helper.appendingPathComponent("EmbeddedPayload", isDirectory: true)
        if fm.fileExists(atPath: embedded.path) { try fm.removeItem(at: embedded) }
        try fm.createDirectory(at: embedded, withIntermediateDirectories: true)
        var embeddedNames: [String] = []

        for (index, entry) in inputs.enumerated() {
            try Task.checkCancellation()
            guard fm.fileExists(atPath: entry.downloadedIPA.path) else {
                throw PreparationError.missingDownload
            }
            try validateArchive(entry.downloadedIPA)
            let unpacked = root.appendingPathComponent("Input-\(index)", isDirectory: true)
            try fm.unzipItem(at: entry.downloadedIPA, to: unpacked)
            let target = try findApp(in: unpacked)
            guard (try info(at: target)["CFBundleIdentifier"] as? String) == entry.bundleID else {
                throw PreparationError.bundleMismatch
            }
            let embeddedName = safePart(entry.name) + "-" + safePart(entry.version) + "-" +
                String(entry.id.uuidString.prefix(8))
            let destination = embedded.appendingPathComponent(embeddedName, isDirectory: true)
            try fm.copyItem(at: target, to: destination)
            let watch = destination.appendingPathComponent("Watch", isDirectory: true)
            if fm.fileExists(atPath: watch.path) { try fm.removeItem(at: watch) }
            try replicateSINF(in: destination)
            embeddedNames.append(embeddedName)
            try fm.removeItem(at: unpacked)
            progress(index + 1)
        }
        let payload = staged.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try fm.moveItem(at: helper,
                        to: payload.appendingPathComponent("FairPlayed.app", isDirectory: true))
        let outputDir = base.appendingPathComponent("Prepared", isDirectory: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let output = outputDir.appendingPathComponent(
            "Velo-Batch-\(inputs.count)-FairPlayed-" + String(UUID().uuidString.prefix(8)) + ".ipa"
        )
        try fm.zipItem(at: staged, to: output, shouldKeepParent: false,
                       compressionMethod: .deflate)
        let archived = try Archive(url: output, accessMode: .read)
        // Apps often contain nested Frameworks/*.framework/Info.plist.
        // Counting ALL nested Info.plist entries was a false-positive and
        // rejected a perfectly valid multi-app helper. Only count each direct
        // EmbeddedPayload/<app>/Info.plist file, exactly one level down.
        let expectedNames = Set(embeddedNames)
        var verifiedNames = Set<String>()
        for archiveEntry in archived {
            guard let marker = archiveEntry.path.range(of: "/EmbeddedPayload/") else { continue }
            let relativePath = archiveEntry.path[marker.upperBound...]
            let parts = relativePath.split(separator: "/")
            if parts.count == 2, parts[1] == "Info.plist" {
                verifiedNames.insert(String(parts[0]))
            }
        }
        guard expectedNames.count == inputs.count, verifiedNames == expectedNames else {
            try? fm.removeItem(at: output)
            throw PreparationError.batchArchiveMismatch(expected: inputs.count,
                                                        found: verifiedNames.count)
        }
        return output
    }

    private static func validateArchive(_ file: URL) throws {
        let zip = try Archive(url: file, accessMode: .read)
        for entry in zip {
            if !safePath(entry.path) { throw PreparationError.unsafeArchive }
        }
    }

    private static func findApp(in root: URL) throws -> URL {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        let items = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
        let apps = items.filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1 else { throw PreparationError.notIPA }
        return apps[0]
    }

    private static func info(at app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw PreparationError.notIPA }
        return dict
    }

    private static func configureHelper(at app: URL, targetName: String) throws {
        let location = app.appendingPathComponent("Info.plist")
        var plist = try info(at: app)
        // Keep the helper bundle ID independent of the target App Store app.
        // Match the known-good per-app FairPlayed packaging used for Tahakom.
        plist["CFBundleIdentifier"] = "com.thehacker.ipastudio.helper"
        plist["CFBundleDisplayName"] = targetName + " Decryptor"
        plist["UIFileSharingEnabled"] = true
        plist["LSSupportsOpeningDocumentsInPlace"] = true
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: location, options: .atomic)
    }

    private static func replicateSINF(in app: URL) throws {
        let manifest = app.appendingPathComponent("SC_Info/Manifest.plist")
        guard fm.fileExists(atPath: manifest.path) else { throw PreparationError.invalidLicense }
        let data = try Data(contentsOf: manifest)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let first = (dict["SinfPaths"] as? [String])?.first,
              safePath(first)
        else { throw PreparationError.invalidLicense }
        let src = app.appendingPathComponent(first)
        guard fm.fileExists(atPath: src.path) else { throw PreparationError.invalidLicense }
        guard let size = try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0
        else { throw PreparationError.invalidLicense }
        for rel in (dict["SinfReplicationPaths"] as? [String]) ?? [] {
            guard safePath(rel) else { throw PreparationError.unsafeArchive }
            if rel.hasPrefix("Watch/") { continue }
            let dst = app.appendingPathComponent(rel)
            if !fm.fileExists(atPath: dst.path) {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dst)
            }
        }
    }

    private static func safePath(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.split(separator: "/").contains("..")
    }

    private static func safePart(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let text = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return text.isEmpty ? "App" : String(text.prefix(70))
    }

    private enum PreparationError: LocalizedError {
        case missingShell, missingDownload, notIPA, invalidShell
        case bundleMismatch, invalidLicense, unsafeArchive, emptyPayload
        case batchArchiveMismatch(expected: Int, found: Int)
        case insufficientSpace(needed: Int64, available: Int64)

        var errorDescription: String? {
            switch self {
            case .missingShell: "FairPlayed is missing from this build. Install the complete R11 IPA."
            case .missingDownload: "The downloaded IPA is missing."
            case .notIPA: "This is not a valid IPA containing one iOS app."
            case .invalidShell: "The built-in FairPlayed helper is invalid."
            case .bundleMismatch: "The download's bundle ID does not match this app."
            case .invalidLicense: "Missing or invalid FairPlay license data."
            case .unsafeArchive: "The IPA contains an unsafe file path."
            case .emptyPayload: "The prepared FairPlayed IPA has no embedded app."
            case let .batchArchiveMismatch(expected, found):
                "Batch IPA verification found \(found) of \(expected) embedded apps."
            case let .insufficientSpace(needed, available):
                "Not enough storage to prepare this batch. Estimated temporary space: \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)); available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)). Free space or select fewer apps."
            }
        }
    }
}
#endif

