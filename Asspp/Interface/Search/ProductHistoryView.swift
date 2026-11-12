//
//  ProductHistoryView.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import SwiftUI

struct ProductHistoryView: View {
    @State var vm: AppPackageArchive
    @State private var showErrorAlert = false
    @State private var downloadingVersions: Set<String> = []
    @State private var downloads = Downloads.this
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            if let message = vm.error, !vm.versionIdentifiers.isEmpty {
                Label("Showing saved versions. Live refresh was unavailable.", systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(message)
                    .listRowBackground(Color.clear)
            }
            if vm.versionIdentifiers.isEmpty && !vm.loading {
                ContentUnavailableView {
                    Label("Version history unavailable", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(vm.error == nil
                        ? "The previous versions have not loaded yet."
                        : "Apple isn't returning an authorized history for this account. Existing saved versions are preserved.")
                } actions: {
                    Button("Retry History") {
                        vm.refreshVersionHistory {
                            await MainActor.run { vm.populateNextVersionItems() }
                        }
                    }
                    .buttonStyle(VeloPillButtonStyle(prominent: true))
                }
                .listRowBackground(Color.clear)
            }
            Section("Previous Versions") {
                ForEach(vm.versionIdentifiers, id: \.self) { key in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.versionItems[key]?.displayVersion ?? "Version ID \(key)")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if let date = vm.versionItems[key]?.releaseDate, date != .distantPast {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let accountID = vm.accountIdentifier, let pkg = vm.package(for: key) {
                        Button {
                            downloadingVersions.insert(key)
                            Task {
                                defer { downloadingVersions.remove(key) }
                                do {
                                    try await Downloads.this.startDownload(for: pkg, accountID: accountID)
                                } catch {
                                    vm.error = error.localizedDescription
                                }
                            }
                        } label: {
                            if let stage = downloads.pendingPreparations.first(where: {
                                $0.key.bundleID == vm.package.software.bundleID && $0.key.version == key
                            })?.value {
                                VStack(spacing: 3) {
                                    ProgressView().controlSize(.mini)
                                    Text(stage.compactLabel)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .accessibilityLabel(stage.statusText)
                            } else if downloadingVersions.contains(key) {
                                ProgressView().tint(.primary)
                            } else {
                                Text("GET")
                            }
                        }
                        .buttonStyle(VeloPillButtonStyle(prominent: true))
                        .disabled(downloadingVersions.contains(key))
                    }
                }
                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            ZStack {
                Rectangle()
                    .foregroundStyle(.clear)
                    .background(.ultraThinMaterial)
                ProgressView()
                    .progressViewStyle(.circular)
                    .smallControlSizeOnMac()
            }
            .opacity(vm.loading && vm.versionIdentifiers.isEmpty ? 1 : 0)
            .animation(.default, value: vm.loading)
            .ignoresSafeArea(edges: [.vertical])
        }
        .animation(.default, value: vm.versionIdentifiers)
        .animation(.default, value: vm.versionItems)
        .animation(.default, value: vm.loading)
        .navigationTitle("Version History")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Menu {
                    Button {
                        vm.populateNextVersionItems()
                    } label: {
                        Label("Load More", systemImage: "arrow.down.circle")
                    }
                    .disabled(vm.isVersionItemsFullyLoaded)
                    Divider()
                    Button(role: .destructive) {
                        vm.refreshVersionHistory {
                            await MainActor.run { vm.populateNextVersionItems() }
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(vm.loading) // just make sure
                .opacity(vm.loading ? 0 : 1)
                .overlay { // using overlay to maintain same size while loading
                    if vm.loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        #if os(macOS)
                            .controlSize(.small)
                        #endif
                    }
                }
            }
        }
        .alert("Oops", isPresented: $showErrorAlert) {
            Button("OK") {
                vm.error = nil
                if vm.shouldDismiss {
                    dismiss()
                }
            }
        } message: {
            Text(vm.error ?? String(localized: "Unknown Error"))
        }
        .onChange(of: vm.error) { _, newValue in
            // Access-denied is persistent, not a useful modal. Show a stable
            // inline explanation and preserve any cached IDs instead.
            showErrorAlert = newValue != nil &&
                !(newValue?.contains("HTTP 403") ?? false)
        }
        .onAppear {
            if vm.versionIdentifiers.isEmpty {
                vm.populateVersionIdentifiers {
                    await MainActor.run { vm.populateNextVersionItems() }
                }
            } else if !vm.isVersionItemsFullyLoaded {
                vm.populateNextVersionItems()
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .automatic
        #endif
    }
}
