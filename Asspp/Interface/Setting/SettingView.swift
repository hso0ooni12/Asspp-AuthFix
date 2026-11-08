//
//  SettingView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

#if canImport(UIKit)
    import UIKit
#endif

struct SettingView: View {
    @Environment(\.openURL) private var openURL
    @State private var vm = AppStore.this
    #if os(iOS)
        @AppStorage("Asspp.AutoPrepareDecrypt") private var autoPrepareDecrypt = false
    #endif

    @State private var showDeviceIdWarning = false
    @State private var editingDeviceId = false
    @State private var deviceIdDraft = ""
    @State private var showResetConfirmation = false
    #if os(iOS)
        @State private var showClearPreparedConfirmation = false
        @State private var decryptor = DecryptionCenter.shared
        @State private var signer = SigningCenter.shared
        @State private var importingIdentity = false
        @State private var showPasswordOptions = false
        @State private var signingPassword = ""
        @State private var signingMessage = ""
        @State private var showSigningMessage = false
        @State private var showRemoveSignerConfirmation = false
    #endif

    var body: some View {
        NavigationStack {
            formContent
        }
    }

    private var normalizedDeviceID: String? {
        AppStore.normalizedDeviceIdentifier(deviceIdDraft)
    }

    private func saveDeviceID() {
        guard let identifier = normalizedDeviceID else { return }
        // The AppStore setter also propagates this to ApplePackage.Configuration.
        vm.deviceIdentifier = identifier
        editingDeviceId = false
    }

    private var formContent: some View {
        Form {
            Section {
                AssppScreenHeader(
                    eyebrow: "ASS•PP  /  CONTROL CENTER",
                    title: "Settings",
                    subtitle: "Manage your signing identity, decryption workflow and privacy.",
                    symbol: "slider.horizontal.3"
                )
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 20))

            #if os(iOS)
                Section {
                    HStack {
                        Image(systemName: signer.isConfigured ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.title2)
                            .foregroundStyle(signer.isConfigured ? .green : AssppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(signer.isConfigured ? "Signing files imported" : "Set up automatic signing")
                                .font(.headline)
                            Text(signer.isConfigured
                                ? "Your certificate and profile are saved on this iPhone."
                                : "Import your P12 certificate and provisioning profile.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button {
                        importingIdentity = true
                    } label: {
                        Label(signer.isConfigured ? "Replace or Add Signing Files" : "Import Signing Files", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AssppTheme.accent)

                    HStack(spacing: 18) {
                        Label(signer.hasCertificate ? "P12 ✓" : "P12 needed",
                              systemImage: signer.hasCertificate ? "checkmark.circle.fill" : "circle.dotted")
                        Label(signer.hasProfile ? "Profile ✓" : "Profile needed",
                              systemImage: signer.hasProfile ? "checkmark.circle.fill" : "circle.dotted")
                    }
                    .font(.caption)
                    .foregroundStyle(signer.isConfigured ? .green : .secondary)

                    DisclosureGroup("Certificate password · only if needed", isExpanded: $showPasswordOptions) {
                        SecureField("Certificate password", text: $signingPassword)
                            .textContentType(.password)
                        Button("Save Password") {
                            do {
                                try signer.savePassword(signingPassword)
                                signingPassword = ""
                                signingMessage = "Certificate password saved securely on your device."
                            } catch {
                                signingMessage = error.localizedDescription
                            }
                            showSigningMessage = true
                        }
                        .disabled(signingPassword.isEmpty)
                        if signer.hasPassword {
                            Button("Clear Saved Password") {
                                signer.clearPassword()
                                signingPassword = ""
                            }
                        }
                        Text("Leave this empty normally. Asspp automatically tries a blank password and the default 1 before asking for a password.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if signer.hasCertificate || signer.hasProfile || signer.hasPassword {
                        Button("Remove Signing Files", role: .destructive) {
                            showRemoveSignerConfirmation = true
                        }
                        .font(.footnote)
                    }
                } header: {
                    Label("AUTO SIGNING", systemImage: "checkmark.shield.fill")
                } footer: {
                    Text("Select both files together, select them separately, or import a ZIP containing the pair. Credentials stay on this device.")
                }
                .listRowBackground(AssppTheme.surface)

                Section {
                    Toggle(isOn: $autoPrepareDecrypt) {
                        Label("Auto Prepare & Sign Decrypt", systemImage: "lock.open.fill")
                    }
                    Button {
                        showClearPreparedConfirmation = true
                    } label: {
                        Label("Clear Prepared Helpers", systemImage: "trash")
                    }
                    Text("Prepared IPA storage: \(ByteCountFormatter.string(fromByteCount: decryptor.preparedStorageSize, countStyle: .file))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("DECRYPTION", systemImage: "lock.open.fill")
                } footer: {
                    Text("When a download finishes, Asspp can prepare its FairPlayed helper and sign it automatically when an identity is configured. Tap Install Signed FairPlayed from the download to begin installation. If signing is unavailable, an unsigned helper is shared instead.")
                }
                .listRowBackground(AssppTheme.surface)
                .confirmationDialog("Remove all prepared FairPlayed helpers?", isPresented: $showClearPreparedConfirmation) {
                    Button("Clear Prepared Helpers", role: .destructive) {
                        decryptor.clearPreparedHelpers()
                    }
                } message: {
                    Text("Downloaded original IPAs and saved signing credentials are kept. Generated FairPlayed IPA files (prepared and signed) are removed.")
                }
            #endif

            Section {
                Toggle("Demo Mode", isOn: $vm.demoMode)
                Button("Delete All Downloads", role: .destructive) {
                    Downloads.this.removeAll()
                }
            } header: {
                Text("GENERAL")
            } footer: {
                Text("Demo mode redacts account details. Deleting downloads leaves signed certificates untouched.")
            }
            .listRowBackground(AssppTheme.surface)

            Section {
                Text(ProcessInfo.processInfo.hostName)
                    .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                if editingDeviceId {
                    TextField("Device GUID", text: $deviceIdDraft)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .onSubmit(saveDeviceID)
                    #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                    #endif
                    if normalizedDeviceID == nil {
                        Text("Enter a valid 12-character hexadecimal device GUID.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    #if os(macOS)
                        HStack {
                            Button("Save") { saveDeviceID() }
                                .disabled(normalizedDeviceID == nil)
                            Button("Cancel", role: .cancel) {
                                editingDeviceId = false
                            }
                            Button("Generate Device GUID") {
                                deviceIdDraft = DeviceIdentifier.random()
                            }
                            Spacer()
                        }
                    #else
                        Button("Save") { saveDeviceID() }
                            .disabled(normalizedDeviceID == nil)
                        Button("Cancel", role: .cancel) {
                            editingDeviceId = false
                        }
                        Button("Generate Device GUID") {
                            deviceIdDraft = DeviceIdentifier.random()
                        }
                    #endif
                } else {
                    HStack {
                        Text(vm.deviceIdentifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                        Spacer()
                        Button("Edit Device GUID") {
                            showDeviceIdWarning = true
                        }
                    }
                    #if os(macOS)
                        HStack {
                            Button("Open Settings") {
                                openURL(URL(string: "x-apple.systempreferences:")!)
                            }
                            Button("Show Certificate in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([Installer.ca])
                            }
                            Spacer()
                        }
                    #else
                        Button("Open Settings") {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        }
                        Button("Install Certificate") {
                            openURL(Installer.caURL)
                        }
                    #endif
                }
            } header: {
                Text("DEVICE & INSTALLATION")
            } footer: {
                #if canImport(UIKit)
                    Text("Grant local network permission to install apps. Install and trust the SSL certificate for on-device installation.")
                #else
                    Text("Grant local network permission to install apps. Install the SSL certificate through System Keychain.")
                #endif
            }
            .listRowBackground(AssppTheme.surface)
            .alert("Edit Device GUID", isPresented: $showDeviceIdWarning) {
                Button("Edit", role: .destructive) {
                    deviceIdDraft = vm.deviceIdentifier
                    editingDeviceId = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changing the device GUID may cause all existing accounts to stop working. Apple limits the number of devices you can sign in with at once.")
            }

            Section {
                Button("Reset", role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text("RESET")
            } footer: {
                Text("This will reset all your settings.")
            }
            .listRowBackground(AssppTheme.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AssppTheme.background)
        .tint(AssppTheme.accent)
        .navigationTitle("Settings")
        #if os(iOS)
        .sheet(isPresented: $importingIdentity) {
            // UIKit's import-as-copy picker accepts security files from Files
            // providers which the generic SwiftUI `.item` importer greyed out.
            SigningDocumentPicker { result in
                importingIdentity = false
                switch result {
                case let .success(urls):
                    do {
                        signingMessage = try signer.importFiles(urls)
                    } catch {
                        signingMessage = error.localizedDescription
                    }
                case let .failure(error):
                    signingMessage = error.localizedDescription
                }
                showSigningMessage = true
            }
        }
        .alert("Signing Identity", isPresented: $showSigningMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signingMessage)
        }
        .confirmationDialog("Remove locally stored signing credentials?", isPresented: $showRemoveSignerConfirmation) {
            Button("Remove Signing Identity", role: .destructive) {
                signer.clear()
            }
        } message: {
            Text("The existing signed IPA files will not be removed.")
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink {
                    LogView()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            }
        }
        .alert("Reset Application", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                try? FileManager.default.removeItem(at: documentsDirectory)
                try? FileManager.default.removeItem(at: temporaryDirectory)
                #if canImport(UIKit)
                    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                #endif
                #if canImport(AppKit) && !canImport(UIKit)
                    NSApp.terminate(nil)
                #endif
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    exit(0)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all your settings and data. The app will close afterwards.")
        }
    }
}

#if os(iOS)
private struct SigningDocumentPicker: UIViewControllerRepresentable {
    let onPicked: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // An unrestrictive picker avoids dimming the P12/mobileprovision files
        // that some third-party Files providers expose under unknown UTTypes.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (Result<[URL], Error>) -> Void
        init(onPicked: @escaping (Result<[URL], Error>) -> Void) {
            self.onPicked = onPicked
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { return }
            onPicked(.success(urls))
        }
    }
}
#endif
