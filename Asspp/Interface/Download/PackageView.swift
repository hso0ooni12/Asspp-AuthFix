//
//  PackageView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
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

    var archive: AppStore.AppPackage {
        pkg.package
    }

    var url: URL {
        pkg.targetLocation
    }

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
        Form {
            Section {
                AssppScreenHeader(
                    eyebrow: "IPA  /  PACKAGE DETAILS",
                    title: archive.software.name,
                    subtitle: "Manage, decrypt and install your downloaded IPA.",
                    symbol: "shippingbox.fill"
                )
            }
            .listRowBackground(Color.clear)
            Section {
                ArchivePreviewView(archive: archive)
            } header: {
                Text("Package")
            }

            Section {
                CopyableRow(label: "Bundle ID", value: archive.software.bundleID, monospaced: true)
                Text("Version")
                    .badge(archive.software.version)
                Text("Developer")
                    .badge(archive.software.sellerName)
                if !archive.software.primaryGenreName.isEmpty {
                    Text("Category")
                        .badge(archive.software.primaryGenreName)
                }
                Text("Compatibility")
                    .badge("\(archive.software.minimumOsVersion)+")
                if archive.software.userRatingCount > 0 {
                    Text("Rating")
                        .badge("\(String(format: "%.1f", archive.software.averageUserRating)) (\(archive.software.userRatingCount))")
                }
            } header: {
                Text("Details")
            }

            if pkg.completed {
                #if os(macOS)
                    DeviceCTLInstallSection(package: pkg)
                #endif
                #if os(iOS)
                    Section {
                        AsyncButton {
                            installer = try await Installer(archive: archive, path: url)
                        } label: {
                            Text("Install")
                        }
                        .disabledWhenLoading()
                        .sheet(item: $installer) {
                            installer?.destroy()
                            installer = nil
                        } content: {
                            InstallerView(installer: $0)
                        }

                        Button("Install via AirDrop") {
                            let newUrl = temporaryDirectory
                                .appendingPathComponent("\(archive.software.bundleID)-\(archive.software.version)")
                                .appendingPathExtension("ipa")
                            try? FileManager.default.removeItem(at: newUrl)
                            try? FileManager.default.copyItem(at: url, to: newUrl)
                            AirDrop(items: [newUrl])
                        }
                    } header: {
                        Text("Control")
                    } footer: {
                        if error.isEmpty {
                            Text("Direct install may have limitations that cannot be bypassed. Use AirDrop if possible on another device.")
                        } else {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                #endif

                #if os(iOS)
                    Section {
                        Button {
                            decryptor.prepare(pkg)
                        } label: {
                            Label(
                                decryptor.status(for: pkg) == .preparing ? "Preparing FairPlayed..." : "Decrypt IPA",
                                systemImage: "lock.open.fill"
                            )
                        }
                        .disabled(decryptor.status(for: pkg) == .preparing)

                        switch decryptor.status(for: pkg) {
                        case .preparing:
                            ProgressView("Preparing and signing FairPlayed...")
                        case .signed:
                            Button {
                                decryptor.install(pkg)
                            } label: {
                                Label("Install Signed FairPlayed", systemImage: "square.and.arrow.down.fill")
                            }
                            Button {
                                decryptor.shareExisting(pkg)
                            } label: {
                                Label("Share Signed IPA", systemImage: "square.and.arrow.up")
                            }
                        case .ready:
                            Button {
                                decryptor.shareExisting(pkg)
                            } label: {
                                Label("Share Prepared IPA", systemImage: "square.and.arrow.up")
                            }
                        case let .failed(message):
                            Text(message).font(.footnote).foregroundStyle(.red)
                        case .idle:
                            EmptyView()
                        }
                    } header: {
                        Text("FairPlay Decryption")
                    } footer: {
                        Text("With a certificate and profile saved in Settings, Asspp prepares and signs the FairPlayed helper on this iPhone, then offers Install. If no signing identity is configured, you can still share the unsigned helper for external signing. Opening FairPlayed automatically decrypts and shares a complete IPA; an incomplete export is never shared.")
                    }
                #endif

                Section {
                    NavigationLink("Content Viewer") {
                        FileListView(packageURL: pkg.targetLocation)
                    }
                    #if os(macOS)
                        HStack {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Text(url.path)
                                    .multilineTextAlignment(.leading)
                            }
                            .help("Show in Finder")
                            .buttonStyle(.borderless)
                            .tint(.accentColor)
                            Spacer()
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(url.path, forType: .string)
                                copied = true
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1))
                                    copied = false
                                }
                            } label: {
                                Image(systemName: copied ? "checkmark" : "document.on.document")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .help("Copy File Path")
                            .buttonStyle(.borderless)
                            .tint(.accentColor)
                        }
                    #endif
                } header: {
                    Text("Analysis")
                } footer: {
                    Text("Developer options.")
                }
            } else {
                Section {
                    let actions = downloads.getAvailableActions(for: pkg)
                    ForEach(actions.filter { $0 != .delete }, id: \.self) { action in
                        let label = downloads.getActionLabel(for: action)
                        Button(label.title) {
                            downloads.performDownloadAction(for: pkg, action: action)
                        }
                        .foregroundStyle(label.isDestructive ? .red : .primary)
                    }
                } header: {
                    Text("Incomplete Package")
                } footer: {
                    switch pkg.state.status {
                    case .pending:
                        Text("\(Int(pkg.state.percent * 100))%...")
                    case .downloading:
                        Text("\(Int(pkg.state.percent * 100))%...")
                    case .paused:
                        Text("Paused at \(Int(pkg.state.percent * 100))%")
                    case .completed:
                        Group {}
                    case .failed:
                        Text("Download failed.")
                    }
                }
            }

            Section {
                Text(pkg.account.account.email)
                    .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                Text("\(pkg.account.account.store) - \(ApplePackage.Configuration.countryCode(for: pkg.account.account.store) ?? String(localized: "Unknown"))")
            } header: {
                Text("Account")
            } footer: {
                Text("This account is used to download this package. If you choose to AirDrop, your target device must sign in or previously signed in to this account and have at least one app installed.")
            }

            Section {
                let deleteAction = DownloadAction.delete
                let label = downloads.getActionLabel(for: deleteAction)
                Button(label.title) {
                    Task { downloads.performDownloadAction(for: pkg, action: deleteAction) }
                    dismiss()
                }
                .foregroundStyle(label.isDestructive ? .red : .primary)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text(url.path)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AssppTheme.background)
        .tint(AssppTheme.accent)
        .navigationTitle(pkg.package.software.name)
    }
}

#if os(iOS)
struct PreparedDecryptionPackage: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct PendingHelperInstallation {
    let manifest: PackageManifest
    let bundleID: String
}

struct AssppActivityShare: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum DecryptionPreparationStatus: Equatable {
    case idle, preparing, ready, signed, failed(String)
}

/// Shared, main-actor coordination prevents duplicate helper exports from the
/// detail view, context menu, swipe actions and automatic post-download flow.
@MainActor
@Observable
final class DecryptionCenter {
    static let shared = DecryptionCenter()

    var statuses: [UUID: DecryptionPreparationStatus] = [:]
    var sharePackage: PreparedDecryptionPackage?
    var installer: Installer?
    var pendingInstall: PendingHelperInstallation?

    @ObservationIgnored private var running: Set<UUID> = []

    private init() {}

    func status(for manifest: PackageManifest) -> DecryptionPreparationStatus {
        if let stored = statuses[manifest.id] { return stored }
        guard preparedURL(for: manifest) != nil else { return .idle }
        return signedURL(for: manifest) != nil ? .signed : .ready
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

    func signedURL(for manifest: PackageManifest) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "Asspp.SignedFairPlayed.\(manifest.id.uuidString)") else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func install(_ manifest: PackageManifest) {
        guard let file = signedURL(for: manifest) else {
            statuses[manifest.id] = .failed("No signed IPA found. Prepare Decrypt again.")
            return
        }
        do {
            let identifier = try Self.helperBundleID(in: file)
            if identifier != "com.thehacker.ipastudio.helper" {
                // An exact provisioning profile might be assigned to an app
                // already installed on this iPhone. Never replace that app
                // without an explicit choice from the user.
                pendingInstall = PendingHelperInstallation(manifest: manifest, bundleID: identifier)
                return
            }
            startInstall(manifest, file: file, bundleID: identifier)
        } catch {
            statuses[manifest.id] = .failed("Cannot validate the signed helper: \(error.localizedDescription)")
        }
    }

    func confirmPendingInstall() {
        guard let request = pendingInstall else { return }
        pendingInstall = nil
        guard let file = signedURL(for: request.manifest) else {
            statuses[request.manifest.id] = .failed("Signed IPA not found. Prepare it again.")
            return
        }
        do {
            guard try Self.helperBundleID(in: file) == request.bundleID else {
                statuses[request.manifest.id] = .failed("Signed IPA changed. Review it and try again.")
                return
            }
            startInstall(request.manifest, file: file, bundleID: request.bundleID)
        } catch {
            statuses[request.manifest.id] = .failed("Cannot validate the signed helper: \(error.localizedDescription)")
        }
    }

    private func startInstall(_ manifest: PackageManifest, file: URL, bundleID: String) {
        Task {
            do {
                installer = try await Installer(
                    archive: manifest.package,
                    path: file,
                    installBundleID: bundleID,
                    installName: manifest.package.software.name + " Decryptor",
                    installVersion: "1.0"
                )
            } catch {
                statuses[manifest.id] = .failed("Installer unavailable: \(error.localizedDescription). Share the signed IPA instead.")
            }
        }
    }

    private static func helperBundleID(in url: URL) throws -> String {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["Payload/FairPlayed.app/Info.plist"],
              entry.uncompressedSize <= 1_048_576 else {
            throw NSError(domain: "AssppSigner", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "The IPA has no valid helper Info.plist."])
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard chunk.count <= 1_048_576 - data.count else {
                throw NSError(domain: "AssppSigner", code: 12,
                              userInfo: [NSLocalizedDescriptionKey: "The helper Info.plist is too large."])
            }
            data.append(chunk)
        }
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              !identifier.isEmpty else {
            throw NSError(domain: "AssppSigner", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "The signed helper is missing its bundle ID."])
        }
        return identifier
    }

    func prepare(_ manifest: PackageManifest) {
        guard manifest.completed, running.insert(manifest.id).inserted else { return }
        statuses[manifest.id] = .preparing
        let input = manifest.targetLocation
        let bundleID = manifest.package.software.bundleID
        let appName = manifest.package.software.name
        let appVersion = manifest.package.software.version
        let storageKey = key(for: manifest)
        let id = manifest.id
        let signingAssets = SigningCenter.shared.credentials()

        Task {
            do {
                let preparation = try await Task.detached(priority: .userInitiated) {
                    let unsigned = try FairPlayedHelper.prepare(
                        downloadedIPA: input,
                        expectedBundleID: bundleID,
                        name: appName,
                        version: appVersion
                    )
                    guard let signingAssets else { return (unsigned, false, String?.none) }
                    do {
                        let signed = try AssppSigner.sign(unsigned, assets: signingAssets)
                        return (signed, true, String?.none)
                    } catch {
                        return (unsigned, false, String?(error.localizedDescription))
                    }
                }.value
                let (output, didSign, signingError) = preparation
                // Keep a single prepared helper per download, but never touch
                // anything the user has already saved outside Asspp's folder.
                if let previous = UserDefaults.standard.string(forKey: storageKey),
                   previous != output.path,
                   URL(fileURLWithPath: previous).deletingLastPathComponent() ==
                       documentsDirectory.appendingPathComponent("FairPlayed/Prepared", isDirectory: true) {
                    try? FileManager.default.removeItem(atPath: previous)
                }
                UserDefaults.standard.set(output.path, forKey: storageKey)
                if didSign {
                    UserDefaults.standard.set(output.path, forKey: "Asspp.SignedFairPlayed.\(id.uuidString)")
                    statuses[id] = .signed
                } else if let signingError {
                    statuses[id] = .failed("Auto signing failed: \(signingError). Unsigned IPA available to share.")
                    sharePackage = PreparedDecryptionPackage(url: output)
                } else {
                    statuses[id] = .ready
                    sharePackage = PreparedDecryptionPackage(url: output)
                }
            } catch {
                statuses[id] = .failed(error.localizedDescription)
            }
            running.remove(id)
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
        return (files + signed).reduce(0) { sum, file in
            sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearPreparedHelpers() {
        for name in ["Prepared", "Signed"] {
            let dir = documentsDirectory.appendingPathComponent("FairPlayed/\(name)", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "ipa" {
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

/// PKCS#12/private key data and the provisioning profile stay in this device's
/// Keychain. Nothing is uploaded or included in GitHub Actions builds.
@MainActor
@Observable
final class SigningCenter {
    static let shared = SigningCenter()
    private static let service = "wiki.qaq.Asspp.AuthFix.R12Signer"
    private static let certificateKey = "p12"
    private static let profileKey = "mobileprovision"
    private static let passwordKey = "p12-password"

    private(set) var hasCertificate = false
    private(set) var hasProfile = false
    private(set) var hasPassword = false

    private init() { refresh() }

    func refresh() {
        hasCertificate = Self.read(Self.certificateKey) != nil
        hasProfile = Self.read(Self.profileKey) != nil
        hasPassword = Self.read(Self.passwordKey) != nil
    }

    // PKCS#12 supports an empty password. The signing library accepts an
    // empty C string, so users only need to save a password when their
    // certificate is actually password-protected.
    var isConfigured: Bool { hasCertificate && hasProfile }

    enum Item { case certificate, profile }

    func importFile(_ url: URL, as item: Item) throws {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= 2_000_000 else {
            throw NSError(domain: "AssppSigner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Certificate/profile is empty or unexpectedly large."])
        }
        try Self.save(data, name: item == .certificate ? Self.certificateKey : Self.profileKey)
        refresh()
    }

    func savePassword(_ password: String) throws {
        if password.isEmpty {
            clearPassword()
            return
        }
        try Self.save(Data(password.utf8), name: Self.passwordKey)
        refresh()
    }

    func clearPassword() {
        SecItemDelete(Self.query(Self.passwordKey) as CFDictionary)
        refresh()
    }

    func credentials() -> AssppSigningAssets? {
        guard let certificate = Self.read(Self.certificateKey),
              let profile = Self.read(Self.profileKey)
        else { return nil }
        let passwordText = Self.read(Self.passwordKey).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return AssppSigningAssets(certificate: certificate, profile: profile, password: passwordText)
    }

    func clear() {
        for name in [Self.certificateKey, Self.profileKey, Self.passwordKey] {
            SecItemDelete(Self.query(name) as CFDictionary)
        }
        refresh()
    }

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    private static func read(_ name: String) -> Data? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &data) == errSecSuccess else { return nil }
        return data as? Data
    }

    private static func save(_ data: Data, name: String) throws {
        let query = query(name)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "AssppSigner", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not securely save the signing identity (\(status))."])
        }
    }
}

struct AssppSigningAssets: Sendable {
    let certificate: Data
    let profile: Data
    let password: String
}

@_silgen_name("AssppSignIPA")
private func assppNativeSign(_ input: UnsafePointer<CChar>,
                             _ p12: UnsafePointer<CChar>,
                             _ password: UnsafePointer<CChar>,
                             _ profile: UnsafePointer<CChar>,
                             _ output: UnsafePointer<CChar>,
                             _ work: UnsafePointer<CChar>,
                             _ message: UnsafeMutablePointer<CChar>,
                             _ capacity: Int32) -> Int32

enum AssppSigner {
    static func sign(_ input: URL, assets: AssppSigningAssets) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("AssppSigning-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let certificate = work.appendingPathComponent("identity.p12")
        let profile = work.appendingPathComponent("profile.mobileprovision")
        try assets.certificate.write(to: certificate, options: .atomic)
        try assets.profile.write(to: profile, options: .atomic)

        let outputs = documentsDirectory.appendingPathComponent("FairPlayed/Signed", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        let output = outputs.appendingPathComponent("FairPlayed-signed-\(UUID().uuidString.prefix(8)).ipa")
        var message = [CChar](repeating: 0, count: 512)
        let messageCapacity = Int32(message.count)
        let result = input.path.withCString { inputPointer in
            certificate.path.withCString { certificatePointer in
                assets.password.withCString { passwordPointer in
                    profile.path.withCString { profilePointer in
                        output.path.withCString { outputPointer in
                            work.path.withCString { workPointer in
                                assppNativeSign(inputPointer, certificatePointer, passwordPointer,
                                                profilePointer, outputPointer, workPointer,
                                                &message, messageCapacity)
                            }
                        }
                    }
                }
            }
        }
        guard result == 0, fm.fileExists(atPath: output.path) else {
            try? fm.removeItem(at: output)
            let explanation = String(cString: message)
            throw NSError(domain: "AssppSigner", code: Int(result), userInfo: [NSLocalizedDescriptionKey: explanation.isEmpty ? "Signing failed." : explanation])
        }
        return output
    }
}

/// CI bundles the pinned, empty FairPlayed shell with Asspp. No user file picker.
enum FairPlayedHelper {
    private static let fm = FileManager.default
    private static var base: URL {
        documentsDirectory.appendingPathComponent("FairPlayed", isDirectory: true)
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
            }
        }
    }
}
#endif
