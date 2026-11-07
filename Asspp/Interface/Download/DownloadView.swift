//
//  DownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct DownloadView: View {
    @State private var vm = Downloads.this

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Downloads")
        }
    }

    private var content: some View {
        Group {
            if vm.manifests.isEmpty {
                ContentUnavailableView(
                    label: {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    },
                    description: {
                        Text("Search for an app or add a download link to get started.")
                    },
                    actions: {
                        NavigationLink("Add Download") {
                            AddDownloadView()
                        }
                    },
                )
                .padding()
            } else {
                Form {
                    packageList
                }
            }
        }
        .formStyle(.grouped)
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .toolbar {
            NavigationLink(destination: AddDownloadView()) {
                Image(systemName: "plus")
            }
        }
    }

    private var packageList: some View {
        ForEach(vm.manifests, id: \.id) { req in
            PackageManifestRow(manifest: req)
        }
    }
}

private struct PackageManifestRow: View {
    let manifest: PackageManifest
    @State private var vm = Downloads.this
    @State private var decryptor = DecryptionCenter.shared
    @State private var showDeleteConfirmation = false
    @State private var showDetails = false
    @State private var shareOriginal: PreparedDecryptionPackage?

    var body: some View {
        NavigationLink(value: manifest) {
            VStack(spacing: 8) {
                ArchivePreviewView(archive: manifest.package)
                SimpleProgress(progress: manifest.state.percent)
                    .animation(.interactiveSpring, value: manifest.state.percent)
                HStack {
                    switch decryptor.status(for: manifest) {
                    case .preparing:
                        Label("Preparing FairPlayed...", systemImage: "lock.open.fill")
                            .foregroundStyle(.blue)
                    case .ready:
                        Label("Ready to Sign", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    case .signed:
                        Label("Ready to Install", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    case let .failed(message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    case .idle:
                        Text(manifest.hint)
                    }
                    Spacer()
                    Text(manifest.creation.formatted())
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if manifest.completed {
                Button {
                    decryptor.prepare(manifest)
                } label: {
                    Label("Decrypt IPA", systemImage: "lock.open.fill")
                }
                .disabled(decryptor.status(for: manifest) == .preparing)

                if decryptor.preparedURL(for: manifest) != nil {
                    Button {
                        decryptor.shareExisting(manifest)
                    } label: {
                        Label("Share Prepared IPA", systemImage: "square.and.arrow.up")
                    }
                }

                if decryptor.signedURL(for: manifest) != nil {
                    Button {
                        decryptor.install(manifest)
                    } label: {
                        Label("Install Signed FairPlayed", systemImage: "square.and.arrow.down")
                    }
                }

                Button {
                    shareOriginal = PreparedDecryptionPackage(url: manifest.targetLocation)
                } label: {
                    Label("Share Original IPA", systemImage: "square.and.arrow.up.on.square")
                }

                Button {
                    showDetails = true
                } label: {
                    Label("App Details", systemImage: "info.circle")
                }
                Divider()
            }
            let actions = vm.getAvailableActions(for: manifest)
            ForEach(actions, id: \.self) { action in
                let label = vm.getActionLabel(for: action)
                Button(role: label.isDestructive ? .destructive : .none) {
                    if action == .delete {
                        showDeleteConfirmation = true
                    } else {
                        vm.performDownloadAction(for: manifest, action: action)
                    }
                } label: {
                    Label(label.title, systemImage: label.systemImage)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if manifest.completed {
                Button {
                    decryptor.prepare(manifest)
                } label: {
                    Label("Decrypt", systemImage: "lock.open.fill")
                }
                .tint(.blue)
                .disabled(decryptor.status(for: manifest) == .preparing)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this download?", isPresented: $showDeleteConfirmation) {
            Button("Delete Download", role: .destructive) {
                vm.delete(request: manifest)
            }
        } message: {
            Text("The downloaded IPA will be removed. A previously prepared FairPlayed helper is retained.")
        }
        .sheet(item: $shareOriginal) { item in
            AssppActivityShare(items: [item.url])
        }
        .navigationDestination(isPresented: $showDetails) {
            PackageView(pkg: manifest)
        }
    }
}

extension PackageManifest {
    var hint: String {
        if let error = state.error {
            return error
        }
        return switch state.status {
        case .pending:
            String(localized: "Pending...")
        case .downloading:
            [
                String(Int(state.percent * 100)) + "%",
                state.speed.isEmpty ? "" : state.speed + "/s",
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        case .paused:
            String(localized: "Paused")
        case .completed:
            String(localized: "Completed")
        case .failed:
            String(localized: "Failed")
        }
    }
}
