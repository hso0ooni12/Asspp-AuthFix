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
        @State private var isPreparingDecryption = false
        @State private var sharePreparedPackage: PreparedDecryptionPackage?
        @State private var decryptionError: String?
    #endif
    #if os(macOS)
        @State private var copied = false
    #endif

    @State private var vm = AppStore.this
    @State private var downloads = Downloads.this

    var body: some View {
        Form {
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
                            prepareDecryptionHelper()
                        } label: {
                            Label(
                                isPreparingDecryption ? "Preparing FairPlayed..." : "Decrypt IPA",
                                systemImage: "lock.open.fill"
                            )
                        }
                        .disabled(isPreparingDecryption)

                        if let decryptionError {
                            Text(decryptionError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("FairPlay Decryption")
                    } footer: {
                        Text("Asspp prepares a FairPlayed helper for this download. Sign and install the helper with eSign. When opened, it decrypts automatically and shows the Share sheet for the complete IPA. If any encrypted component fails, no partial IPA is exported. Your Apple ID must own the target app.")
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
        .navigationTitle(pkg.package.software.name)
        #if os(iOS)
            .sheet(item: $sharePreparedPackage) { prepared in
                AssppActivityShare(items: [prepared.url])
            }
        #endif
    }

    #if os(iOS)
        private func prepareDecryptionHelper() {
            guard !isPreparingDecryption else { return }
            isPreparingDecryption = true
            decryptionError = nil
            let url = pkg.targetLocation
            let bundle = archive.software.bundleID
            let name = archive.software.name
            let version = archive.software.version

            Task {
                do {
                    let file = try await Task.detached(priority: .userInitiated) {
                        try FairPlayedHelper.prepare(downloadedIPA: url, expectedBundleID: bundle, name: name, version: version)
                    }.value
                    sharePreparedPackage = PreparedDecryptionPackage(url: file)
                } catch {
                    decryptionError = error.localizedDescription
                }
                isPreparingDecryption = false
            }
        }
    #endif
}

#if os(iOS)
private struct PreparedDecryptionPackage: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct AssppActivityShare: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// CI bundles the pinned, empty FairPlayed shell with Asspp. No user file picker.
private enum FairPlayedHelper {
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
            case .missingShell: "FairPlayed is missing from this build. Install the complete R10 IPA."
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
