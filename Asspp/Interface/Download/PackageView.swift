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
import UniformTypeIdentifiers
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
        @State private var templateReady = IPAStudioHelper.hasTemplate
        @State private var isPreparingDecryption = false
        @State private var selectIPAStudioTemplate = false
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
                            if templateReady {
                                prepareDecryptionHelper()
                            } else {
                                selectIPAStudioTemplate = true
                            }
                        } label: {
                            Label(
                                isPreparingDecryption ? "Preparing IPA Studio..." : "Decrypt IPA",
                                systemImage: "lock.open.fill"
                            )
                        }
                        .disabled(isPreparingDecryption)

                        if templateReady {
                            Button("Change IPA Studio Template") {
                                selectIPAStudioTemplate = true
                            }
                            .font(.footnote)
                        } else {
                            Text("One-time setup: choose the original IPA Studio .ipa we built earlier. This file stays on your iPhone.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let decryptionError {
                            Text(decryptionError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("FairPlay Decryption")
                    } footer: {
                        Text("Asspp prepares IPA Studio with this downloaded app inside. Share the new IPA with eSign, sign and install it, then open IPA Studio to decrypt and export. You need an Apple ID license for the target app.")
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
            .fileImporter(isPresented: $selectIPAStudioTemplate, allowedContentTypes: [.item]) { result in
                switch result {
                case let .success(url):
                    do {
                        try IPAStudioHelper.importTemplate(from: url)
                        templateReady = true
                        decryptionError = nil
                        prepareDecryptionHelper()
                    } catch {
                        decryptionError = error.localizedDescription
                    }
                case let .failure(error):
                    decryptionError = error.localizedDescription
                }
            }
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
                        try IPAStudioHelper.prepare(downloadedIPA: url, expectedBundleID: bundle, name: name, version: version)
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

/// The user provides their own IPA Studio build once. No FairPlayed code or
/// binary is embedded into Asspp or uploaded to a server.
private enum IPAStudioHelper {
    private static let fm = FileManager.default
    private static var base: URL {
        documentsDirectory.appendingPathComponent("IPAStudio", isDirectory: true)
    }
    private static var template: URL {
        base.appendingPathComponent("IPAStudioTemplate.ipa")
    }
    static var hasTemplate: Bool { fm.fileExists(atPath: template.path) }

    static func importTemplate(from input: URL) throws {
        let accessGranted = input.startAccessingSecurityScopedResource()
        defer { if accessGranted { input.stopAccessingSecurityScopedResource() } }
        let scratch = fm.temporaryDirectory.appendingPathComponent("StudioValidate-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        try validateArchive(input)
        try fm.unzipItem(at: input, to: scratch)
        let app = try findApp(in: scratch)
        let plist = try info(at: app)
        let executable = (plist["CFBundleExecutable"] as? String ?? "").lowercased()
        let displayName = (plist["CFBundleDisplayName"] as? String ?? "").lowercased()
        let bundleID = (plist["CFBundleIdentifier"] as? String ?? "").lowercased()
        guard executable.contains("fairplayed") || displayName.contains("ipa studio")
            || displayName.contains("fairplayed") || bundleID.contains("fairplayed")
            || bundleID.contains("ipastudio")
        else { throw PreparationError.wrongTemplate }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let copy = base.appendingPathComponent(UUID().uuidString + ".ipa")
        try fm.copyItem(at: input, to: copy)
        if hasTemplate { try fm.removeItem(at: template) }
        try fm.moveItem(at: copy, to: template)
    }

    static func prepare(downloadedIPA: URL, expectedBundleID: String, name: String, version: String) throws -> URL {
        guard hasTemplate else { throw PreparationError.missingTemplate }
        guard fm.fileExists(atPath: downloadedIPA.path) else { throw PreparationError.missingDownload }
        let root = fm.temporaryDirectory.appendingPathComponent("StudioBuild-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let staged = root.appendingPathComponent("Staged", isDirectory: true)
        let input = root.appendingPathComponent("Input", isDirectory: true)
        try validateArchive(template)
        try validateArchive(downloadedIPA)
        try fm.unzipItem(at: template, to: staged)
        try fm.unzipItem(at: downloadedIPA, to: input)
        let studio = try findApp(in: staged)
        let target = try findApp(in: input)
        guard (try info(at: target)["CFBundleIdentifier"] as? String) == expectedBundleID else {
            throw PreparationError.bundleMismatch
        }
        let embedded = studio.appendingPathComponent("EmbeddedPayload", isDirectory: true)
        if fm.fileExists(atPath: embedded.path) { try fm.removeItem(at: embedded) }
        try fm.createDirectory(at: embedded, withIntermediateDirectories: true)

        // FairPlayed must be signed with the target inside its own app bundle.
        // Dropping .app on the embedded directory keeps encrypted code as resources.
        let copied = embedded.appendingPathComponent(target.deletingPathExtension().lastPathComponent, isDirectory: true)
        try fm.copyItem(at: target, to: copied)
        let watch = copied.appendingPathComponent("Watch", isDirectory: true)
        if fm.fileExists(atPath: watch.path) { try fm.removeItem(at: watch) }
        try replicateSINF(in: copied)

        let outputs = base.appendingPathComponent("Prepared", isDirectory: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
        let output = outputs.appendingPathComponent(
            safePart(name) + "-" + safePart(version) + "-IPAStudio-" + String(UUID().uuidString.prefix(8)) + ".ipa"
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

    private static func replicateSINF(in app: URL) throws {
        let manifest = app.appendingPathComponent("SC_Info/Manifest.plist")
        guard fm.fileExists(atPath: manifest.path) else { return }
        let data = try Data(contentsOf: manifest)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let first = (dict["SinfPaths"] as? [String])?.first,
              safePath(first)
        else { throw PreparationError.invalidLicense }
        let src = app.appendingPathComponent(first)
        guard fm.fileExists(atPath: src.path) else { throw PreparationError.invalidLicense }
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
        case missingTemplate, missingDownload, notIPA, wrongTemplate
        case bundleMismatch, invalidLicense, unsafeArchive, emptyPayload

        var errorDescription: String? {
            switch self {
            case .missingTemplate: "Choose your original IPA Studio IPA first."
            case .missingDownload: "The downloaded IPA is missing."
            case .notIPA: "This is not a valid IPA containing one iOS app."
            case .wrongTemplate: "Choose the IPA Studio / FairPlayed helper IPA, not an App Store IPA."
            case .bundleMismatch: "The download's bundle ID does not match this app."
            case .invalidLicense: "Missing or invalid FairPlay license data."
            case .unsafeArchive: "The IPA contains an unsafe file path."
            case .emptyPayload: "The prepared IPA Studio has no embedded app."
            }
        }
    }
}
#endif
