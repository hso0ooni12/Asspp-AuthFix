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
    @State private var showBatchError = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                AssppScreenHeader(
                    eyebrow: "VELO  /  IPA MANAGER",
                    title: "Downloads",
                    subtitle: "Downloads, organized.",
                    symbol: "arrow.down.to.line.compact"
                )
                AssppCard {
                    HStack(spacing: 10) {
                        summaryMetric("\(vm.manifests.count)", label: "TOTAL", symbol: "square.stack.3d.up")
                        summaryMetric("\(vm.manifests.filter(\.completed).count)", label: "READY", symbol: "checkmark.seal")
                        summaryMetric("\(vm.activeOperationCount)", label: "ACTIVE", symbol: "arrow.down.circle")
                    }
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
                        } label: {
                            Label(selectedIDs.count == 1 ? "Prepare Decryptor" :
                                    "Prepare One Decryptor (\(selectedIDs.count) Apps)",
                                  systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedIDs.isEmpty || decryptor.isPreparingBatch)
                        Text("Velo builds one FairPlayed IPA for all selected apps. Sign it once; opening it decrypts every app and shares one ZIP of decrypted IPAs.")
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
                        Text("Embedding \(decryptor.batchCompleted) of \(decryptor.batchTotal) apps")
                            .font(.subheadline.bold())
                        ProgressView(value: Double(decryptor.batchCompleted),
                                     total: Double(max(decryptor.batchTotal, 1)))
                            .tint(AssppTheme.accent)
                        Text("Keep Velo open while the single helper is packaged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !vm.pendingPreparations.isEmpty {
                ForEach(Array(vm.pendingPreparations.keys).sorted(by: { $0.bundleID < $1.bundleID }), id: \.self) { key in
                    if let item = vm.pendingPreparations[key] {
                        AssppCard {
                            HStack(spacing: 12) {
                                ProgressView().tint(AssppTheme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.appName).font(.subheadline.bold())
                                    Text(item.stage.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            if vm.manifests.isEmpty && vm.pendingPreparations.isEmpty {
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
            } else if !vm.manifests.isEmpty {
                packageList
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AssppTheme.background)
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .alert("Bulk Preparation", isPresented: $showBatchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(decryptor.batchError ?? "Unable to prepare the selected apps.")
        }
        .onChange(of: decryptor.batchError) { _, message in
            showBatchError = message != nil
        }
        .onChange(of: decryptor.isPreparingBatch) { _, preparing in
            if !preparing, decryptor.batchError == nil, decryptor.batchTotal > 1 {
                selectionMode = false
                selectedIDs.removeAll()
            }
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
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(AssppTheme.accent)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
                    deleteImmediately(id: req.id)
                }
            }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18))
        }
    }

    private func deleteImmediately(id: UUID) {
        // The context menu/swipe action gets one event cycle to dismiss, then
        // the row is removed safely. There is no second confirmation tap.
        Task { @MainActor in
            await Task.yield()
            guard let request = vm.manifests.first(where: { $0.id == id }) else { return }
            selectedIDs.remove(id)
            vm.delete(request: request)
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
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    NavigationLink(value: manifest) {
                        ArchivePreviewView(archive: manifest.package)
                    }
                    .buttonStyle(.plain)
                    if manifest.completed {
                        Button {
                            decryptor.prepare(manifest)
                        } label: {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AssppTheme.accent)
                        .disabled(decryptor.status(for: manifest) == .preparing)
                        .accessibilityLabel("Decrypt IPA")
                    }
                }
                if !manifest.completed {
                    SimpleProgress(progress: manifest.state.percent)
                        .animation(.interactiveSpring, value: manifest.state.percent)
                }
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

