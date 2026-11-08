//
//  DownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct DownloadView: View {
    @State private var vm = Downloads.this
    @State private var decryptor = DecryptionCenter.shared
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var deletionID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var showBatchError = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Downloads")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        List {
            VStack(alignment: .leading, spacing: 18) {
                AssppScreenHeader(
                    eyebrow: "VELO  /  IPA MANAGER",
                    title: "Downloads",
                    subtitle: "Downloads, organized.",
                    symbol: "arrow.down.to.line.compact"
                )
                HStack(spacing: 12) {
                    summaryMetric("\(vm.manifests.count)", label: "TOTAL", symbol: "square.stack.3d.up")
                    summaryMetric("\(vm.manifests.filter(\.completed).count)", label: "READY", symbol: "checkmark.seal")
                    summaryMetric("\(vm.runningTaskCount)", label: "ACTIVE", symbol: "arrow.down.circle")
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if selectionMode {
                AssppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(selectedIDs.count) apps selected")
                                .font(.headline)
                            Spacer()
                            Button("Select All") {
                                selectedIDs = Set(vm.manifests.filter(\.completed).map(\.id))
                            }
                            .font(.subheadline)
                            Button("Clear") { selectedIDs.removeAll() }
                                .font(.subheadline)
                        }
                        Button {
                            let chosen = vm.manifests.filter {
                                $0.completed && selectedIDs.contains($0.id)
                            }
                            decryptor.prepareBatch(chosen)
                            selectionMode = false
                            selectedIDs.removeAll()
                        } label: {
                            Label(selectedIDs.count == 1 ? "Prepare Decryptor" :
                                    "Prepare \(selectedIDs.count) Decryptors as ZIP",
                                  systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedIDs.isEmpty || decryptor.isPreparingBatch)
                        Text("For multiple apps, Velo exports one ZIP of FairPlayed helpers to sign. Each helper decrypts its app after installation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if decryptor.isPreparingBatch {
                AssppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preparing \(decryptor.batchCompleted) of \(decryptor.batchTotal)")
                            .font(.subheadline.bold())
                        ProgressView(value: Double(decryptor.batchCompleted),
                                     total: Double(max(decryptor.batchTotal, 1)))
                            .tint(AssppTheme.accent)
                        Text("Keep Velo open while the helper IPAs are packaged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if vm.manifests.isEmpty {
                AssppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 35))
                            .foregroundStyle(AssppTheme.accent)
                        Text("Your downloads will appear here")
                            .font(.title3.bold())
                        Text("Find apps in Search or add a direct IPA link to begin.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            AddDownloadView()
                        } label: {
                            Label("Add Download", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                packageList
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AssppTheme.background)
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .confirmationDialog("Delete this download?", isPresented: $showDeleteConfirmation) {
            Button("Delete Download", role: .destructive) {
                let id = deletionID
                deletionID = nil
                // Dismiss the swipe/confirmation UI before changing the List.
                Task { @MainActor in
                    await Task.yield()
                    if let id, let request = vm.manifests.first(where: { $0.id == id }) {
                        vm.delete(request: request)
                    }
                }
            }
        } message: {
            Text("The original IPA is removed. Prepared FairPlayed helpers are kept.")
        }
        .alert("Bulk Preparation", isPresented: $showBatchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(decryptor.batchError ?? "Unable to prepare the selected apps.")
        }
        .onChange(of: decryptor.batchError) { _, message in
            showBatchError = message != nil
        }
        .toolbar {
            if !vm.manifests.filter(\.completed).isEmpty {
                Button(selectionMode ? "Done" : "Select") {
                    selectionMode.toggle()
                    if !selectionMode { selectedIDs.removeAll() }
                }
            }
            NavigationLink(destination: AddDownloadView()) {
                Image(systemName: "plus")
            }
        }
    }

    private func summaryMetric(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(AssppTheme.accent)
                .font(.subheadline)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AssppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var packageList: some View {
        ForEach(vm.manifests, id: \.id) { req in
            HStack(spacing: 12) {
                if selectionMode {
                    Button {
                        guard req.completed else { return }
                        if !selectedIDs.insert(req.id).inserted { selectedIDs.remove(req.id) }
                    } label: {
                        Image(systemName: selectedIDs.contains(req.id) ?
                              "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(req.completed ? AssppTheme.accent : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(!req.completed)
                }
                PackageManifestRow(manifest: req) {
                    deletionID = req.id
                    showDeleteConfirmation = true
                }
            }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18))
        }
    }
}

private struct PackageManifestRow: View {
    let manifest: PackageManifest
    let onDelete: () -> Void
    @State private var vm = Downloads.this
    @State private var decryptor = DecryptionCenter.shared
    @State private var showPreparationError = false
    @State private var showDetails = false
    @State private var shareOriginal: PreparedDecryptionPackage?

    var body: some View {
        AssppCard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: manifest) {
                    ArchivePreviewView(archive: manifest.package)
                }
                .buttonStyle(.plain)
                SimpleProgress(progress: manifest.state.percent)
                    .animation(.interactiveSpring, value: manifest.state.percent)
                HStack(spacing: 10) {
                    switch decryptor.status(for: manifest) {
                    case .preparing:
                        Label("Preparing FairPlayed...", systemImage: "lock.open.fill")
                            .foregroundStyle(AssppTheme.accent)
                    case .ready:
                        Label("Ready to Sign", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    case let .failed(message):
                        Button {
                            showPreparationError = true
                        } label: {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                    case .idle:
                        Text(manifest.hint)
                    }
                    Spacer()
                    Text(manifest.creation.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.system(.footnote, design: .rounded))
                .lineLimit(1)

                if manifest.completed {
                    HStack(spacing: 10) {
                        Button {
                            decryptor.prepare(manifest)
                        } label: {
                            Label(decryptor.status(for: manifest) == .preparing ? "Preparing..." : "Decrypt IPA", systemImage: "lock.open.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AssppTheme.accent)
                        .disabled(decryptor.status(for: manifest) == .preparing)
                    }
                }
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
                        onDelete()
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
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Preparation Details", isPresented: $showPreparationError) {
            Button("OK", role: .cancel) {}
        } message: {
            if case let .failed(message) = decryptor.status(for: manifest) {
                Text(message)
            } else {
                Text("No preparation error is currently recorded.")
            }
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
            String(localized: "Queued / Preparing...")
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

