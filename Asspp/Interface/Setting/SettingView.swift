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
                Toggle("Demo Mode", isOn: $vm.demoMode)
                Button("Delete All Downloads", role: .destructive) {
                    Downloads.this.removeAll()
                }
            } header: {
                Text("General")
            } footer: {
                Text("Demo mode redacts all accounts and sensitive information.")
            }

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
                    SecureField(signer.hasPassword ? "P12 password saved • enter to replace" : "P12 certificate password", text: $signingPassword)
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
                    HStack {
                        Image(systemName: signer.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(signer.isConfigured ? Color.green : Color.orange)
                        Text(signer.isConfigured ? "Auto Sign Ready" : "Complete the 3 fields to enable Auto Sign")
                            .font(.footnote)
                    }
                    if signer.hasCertificate || signer.hasProfile || signer.hasPassword {
                        Button("Remove Signing Identity", role: .destructive) {
                            showRemoveSignerConfirmation = true
                        }
                    }
                } header: {
                    Text("On-device IPA Signing")
                } footer: {
                    Text("Your Apple Account remains for App Store downloads. The P12 certificate, profile, and password are stored in this device's Keychain, never uploaded to a server. Once configured, Decrypt also signs FairPlayed automatically. Your profile must support this device and the helper bundle ID.")
                }
                .fileImporter(isPresented: $importingIdentity, allowedContentTypes: [.item]) { result in
                    do {
                        let url = try result.get()
                        try signer.importFile(url, as: importingItem)
                        signingMessage = "Signing file imported."
                    } catch {
                        signingMessage = error.localizedDescription
                    }
                    showSigningMessage = true
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
                    Text("IPA Decryption")
                } footer: {
                    Text("When a download finishes, Asspp can prepare its FairPlayed helper and sign it automatically when an identity is configured. Tap Install Signed FairPlayed from the download to begin installation. If signing is unavailable, an unsigned helper is shared instead.")
                }
                .confirmationDialog("Remove all prepared FairPlayed helpers?", isPresented: $showClearPreparedConfirmation) {
                    Button("Clear Prepared Helpers", role: .destructive) {
                        decryptor.clearPreparedHelpers()
                    }
                } message: {
                    Text("Downloaded original IPAs and saved signing credentials are kept. Generated FairPlayed IPA files (prepared and signed) are removed.")
                }
            #endif

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
                Text("Device")
            } footer: {
                #if canImport(UIKit)
                    Text("Grant local network permission to install apps. Install and trust the SSL certificate for on-device installation.")
                #else
                    Text("Grant local network permission to install apps. Install the SSL certificate through System Keychain.")
                #endif
            }
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
                Text("Danger Zone")
            } footer: {
                Text("This will reset all your settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
