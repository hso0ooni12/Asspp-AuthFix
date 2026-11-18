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
    @State private var showDownloadError = false
    @State private var downloadError = ""
    @State private var downloadingVersions: Set<String> = []
    @State private var downloads = Downloads.this

    var body: some View {
        List {
            Section("Previous Versions") {
                ForEach(vm.verifiedVersionIDs, id: \.self) { identifier in
                    if let version = vm.versionItems[identifier] {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(version.displayVersion)
                                    .font(.body.weight(.medium))
                                if let date = vm.versionItems[identifier]?.releaseDate, date != .distantPast {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            downloadButton(for: identifier)
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                }
                if vm.loading {
                    ProgressView("Checking available versions…")
                } else if vm.canLoadMoreVersions {
                    Button {
                        vm.populateNextVersionItems()
                    } label: {
                        Label("Load More", systemImage: "arrow.down.circle")
                    }
                } else if vm.verifiedVersionIDs.isEmpty {
                    Label("Version history unavailable", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                if let error = vm.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = vm.appStoreURL {
                Link(destination: url) {
                    Label("Version History on the App Store", systemImage: "arrow.up.right.square")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Version History")
        .toolbar {
            if vm.accountIdentifier != nil {
                ToolbarItem(placement: toolbarPlacement) {
                    Button {
                        vm.refreshVersionHistory()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.loading)
                }
            }
        }
        .alert("Download", isPresented: $showDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadError)
        }
        .onAppear {
            if vm.versionIdentifiers.isEmpty {
                vm.populateVersionIdentifiers()
            } else {
                vm.populateNextVersionItems()
            }
        }
    }

    @ViewBuilder
    private func downloadButton(for identifier: String) -> some View {
        if let accountID = vm.accountIdentifier, let package = vm.package(for: identifier) {
            Button {
                downloadingVersions.insert(identifier)
                Task {
                    defer { downloadingVersions.remove(identifier) }
                    do {
                        try await downloads.startDownload(for: package, accountID: accountID)
                    } catch {
                        downloadError = error.localizedDescription
                        showDownloadError = true
                    }
                }
            } label: {
                if let stage = downloads.pendingPreparations.first(where: {
                    $0.key.accountID == accountID && $0.key.appID == package.software.id && $0.key.version == identifier
                })?.value {
                    VStack(spacing: 3) {
                        ProgressView().controlSize(.mini)
                        Text(stage.compactLabel)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .accessibilityLabel(stage.statusText)
                } else if downloadingVersions.contains(identifier) {
                    ProgressView().tint(.primary)
                } else {
                    Text("GET")
                }
            }
            .buttonStyle(VeloPillButtonStyle(prominent: true))
            .disabled(downloadingVersions.contains(identifier))
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
