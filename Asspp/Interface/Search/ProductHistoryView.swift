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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
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
                            if downloadingVersions.contains(key) {
                                ProgressView().tint(.primary)
                            } else {
                                Text("GET")
                            }
                        }
                        .buttonStyle(VeloPillButtonStyle())
                        .disabled(downloadingVersions.contains(key))
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                        vm.clearVersionItems()
                        vm.populateVersionIdentifiers {
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
            showErrorAlert = newValue != nil
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
