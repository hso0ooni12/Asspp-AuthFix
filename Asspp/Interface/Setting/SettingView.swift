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
        @State private var importingItem: SigningCenter.Item = .certificate
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
                        Label("Certificate (.p12)", systemImage: "checkmark.shield")
                        Spacer()
                        Text(signer.hasCertificate ? "Imported" : "Missing")
                            .foregroundStyle(signer.hasCertificate ? Color.green : Color.secondary)
                    }
                    Button("Import P12 Certificate") {
                        importingItem = .certificate
                        importingIdentity = true
                    }
                    HStack {
                        Label("Provisioning Profile", systemImage: "doc.badge.gearshape")
                        Spacer()
                        Text(signer.hasProfile ? "Imported" : "Missing")
                            .foregroundStyle(signer.hasProfile ? Color.green : Color.secondary)
                    }
                    Button("Import Mobileprovision") {
                        importingItem = .profile
                        importingIdentity = true
                    }
                    SecureField(signer.hasPassword ? "Password saved • enter to replace" : "P12 password (optional)", text: $signingPassword)
                        .textContentType(.password)
                    Button(signer.hasPassword ? "Update P12 Password" : "Save P12 Password") {
                        do {
                            try signer.savePassword(signingPassword)
                            signingPassword = ""
                            signingMessage = "Signing password saved securely on this device."
                        } catch {
                            signingMessage = error.localizedDescription
                        }
                        showSigningMessage = true
                    }
                    .disabled(signingPassword.isEmpty)
                    Button {
                        signer.clearPassword()
                        signingPassword = ""
                        signingMessage = "No certificate password will be used. FairPlayed signing will try an empty P12 password."
                        showSigningMessage = true
                    } label: {
                        Label("Use Without Password", systemImage: "lock.open")
                    }
                    HStack {
                        Label(
                            signer.isConfigured
                                ? (signer.hasPassword ? "Signing configured • password saved" : "Signing configured • no password")
                                : "Import the P12 certificate and provisioning profile",
                            systemImage: signer.isConfigured ? "checkmark.shield.fill" : "exclamationmark.shield"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(signer.isConfigured ? AssppTheme.accent : .orange)
                    }
                    if signer.hasCertificate || signer.hasProfile || signer.hasPassword {
                        Button("Remove Signing Identity", role: .destructive) {
                            showRemoveSignerConfirmation = true
                        }
                    }
                } header: {
                    Label("ON-DEVICE SIGNING", systemImage: "checkmark.shield.fill")
                } footer: {
                    Text("A P12 password is optional. If your certificate has no password, leave the field empty or tap Use Without Password. Protected certificates still need the correct password. Signing files are stored only on your device; Decrypt signs FairPlayed automatically when the certificate and profile are present.")
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
            SigningDocumentPicker(item: importingItem) { result in
                importingIdentity = false
                switch result {
                case let .success(url):
                    do {
                        try signer.importFile(url, as: importingItem)
                        signingMessage = "Signing file imported successfully."
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
    let item: SigningCenter.Item
    let onPicked: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let extensions = item == .certificate ? ["p12", "pfx"] : ["mobileprovision", "provisionprofile"]
        var types: [UTType] = extensions.compactMap { UTType(filenameExtension: $0, conformingTo: .data) }
        // These common base types let Files providers expose certificates even
        // when their proprietary UTType is not declared on that provider.
        types.append(contentsOf: [.data, .content, .item])
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (Result<URL, Error>) -> Void
        init(onPicked: @escaping (Result<URL, Error>) -> Void) {
            self.onPicked = onPicked
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(.success(url))
        }
    }
}
#endif
