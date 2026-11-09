//
//  SettingView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

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
    @State private var showDeleteAllConfirmation = false
    @State private var showAdvancedSettings = false
    #if os(iOS)
        @State private var showClearPreparedConfirmation = false
        @State private var decryptor = DecryptionCenter.shared
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
                    eyebrow: "VELO  /  CONTROL CENTER",
                    title: "Settings",
                    subtitle: "Simple controls. Advanced options when needed.",
                    symbol: "slider.horizontal.3"
                )
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 20))

            #if os(iOS)
                Section {
                    Toggle(isOn: $autoPrepareDecrypt) {
                        Label("Auto Prepare Decryptor", systemImage: "lock.open.fill")
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
                    Text("When a download finishes, Velo can prepare and share a FairPlayed helper automatically. The helper must then be signed and installed using your signing app. Decryption starts automatically when the helper opens.")
                }
                .listRowBackground(AssppTheme.surface)
                .confirmationDialog("Remove all prepared FairPlayed helpers?", isPresented: $showClearPreparedConfirmation) {
                    Button("Clear Prepared Helpers", role: .destructive) {
                        decryptor.clearPreparedHelpers()
                    }
                } message: {
                    Text("Downloaded original IPAs are kept. Generated FairPlayed helpers are removed.")
                }
            #endif

            Section {
                Toggle("Demo Mode", isOn: $vm.demoMode)
                Button("Delete All Downloads", role: .destructive) {
                    showDeleteAllConfirmation = true
                }
            } header: {
                Text("GENERAL")
            } footer: {
                Text("Demo mode hides account details. Delete All Downloads removes the original downloaded IPAs.")
            }
            .listRowBackground(AssppTheme.surface)
            .confirmationDialog("Delete all downloaded IPA files?", isPresented: $showDeleteAllConfirmation) {
                Button("Delete All Downloads", role: .destructive) {
                    Downloads.this.removeAll()
                }
            } message: {
                Text("Individual file deletion stays one tap. Removing the whole library cannot be undone.")
            }

            Section {
                DisclosureGroup("Advanced · Device & Installation", isExpanded: $showAdvancedSettings) {
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
                }
            } header: {
                Text("ADVANCED")
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
                Button("Reset Preferences") {
                    showResetConfirmation = true
                }
            } header: {
                Text("PREFERENCES")
            } footer: {
                Text("Restores interface preferences only. Apple accounts and downloaded IPAs stay untouched.")
            }
            .listRowBackground(AssppTheme.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AssppTheme.background)
        .tint(AssppTheme.accent)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink {
                    LogView()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            }
        }
        .alert("Reset Preferences", isPresented: $showResetConfirmation) {
            Button("Reset Preferences") {
                vm.demoMode = false
                #if os(iOS)
                    autoPrepareDecrypt = false
                #endif
                UserDefaults.standard.removeObject(forKey: "searchKey")
                UserDefaults.standard.removeObject(forKey: "searchRegion")
                for key in UserDefaults.standard.dictionaryRepresentation().keys
                    where key.hasPrefix("Velo.PreferredAccount.") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your downloads, FairPlayed helpers and Apple accounts will be preserved.")
        }
    }
}
