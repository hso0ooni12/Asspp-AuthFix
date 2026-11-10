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
                .navigationTitle("Downloads")
        }
    }

    private var content: some View {
        List {
            if selectionMode {
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("All") {
                        selectedIDs = Set(vm.manifests.filter(\.completed).map(\.id))
                    }
                    Button("Clear") { selectedIDs.removeAll() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if decryptor.isPreparingBatch {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preparing \(decryptor.batchCompleted) / \(decryptor.batchTotal)")
                    ProgressView(value: Double(decryptor.batchCompleted),
                                 total: Double(max(decryptor.batchTotal, 1)))
                        .tint(AssppTheme.accent)
                }
            }

            if !vm.pendingPreparations.isEmpty {
                ForEach(Array(vm.pendingPreparations.keys).sorted(by: { $0.bundleID < $1.bundleID }), id: \.self) { key in
                    if let item = vm.pendingPreparations[key] {
                        HStack(spacing: 12) {
                            ProgressView().tint(AssppTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.appName).font(.subheadline.weight(.medium))
                                Text(item.stage.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if vm.manifests.isEmpty && vm.pendingPreparations.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Find an app in Search to begin.")
                } actions: {
                    NavigationLink {
                        AddDownloadView()
                    } label: {
                        Text("Add Download")
                    }
                    .buttonStyle(VeloPillButtonStyle(prominent: true))
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
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                Button {
                    let chosen = vm.manifests.filter { $0.completed && selectedIDs.contains($0.id) }
                    decryptor.prepareBatch(chosen)
                } label: {
                    Text(selectedIDs.count == 1 ? "Prepare Decryptor" : "Prepare \(selectedIDs.count) Apps")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VeloPillButtonStyle(prominent: true))
                .disabled(selectedIDs.isEmpty || decryptor.isPreparingBatch)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
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

    private var packageList: some View {
        Group {
            if vm.manifests.contains(where: { !$0.completed }) {
                Section("Active") {
                    ForEach(vm.manifests.filter { !$0.completed }, id: \.id) { req in
                        manifestRow(req)
                    }
                }
            }
            if vm.manifests.contains(where: \.completed) {
                Section("Ready") {
                    ForEach(vm.manifests.filter(\.completed), id: \.id) { req in
                        manifestRow(req)
                    }
                }
            }
        }
    }

    private func manifestRow(_ req: PackageManifest) -> some View {
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
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
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
        VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    NavigationLink(value: manifest) {
                        ArchivePreviewView(archive: manifest.package,
                                           preferredIconSize: 60, showsVersion: false)
                    }
                    .buttonStyle(.plain)
                    if manifest.completed {
                        Button {
                            decryptor.prepare(manifest)
                        } label: {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 52)
                        }
                        .buttonStyle(VeloPillButtonStyle())
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
                        .foregroundStyle(.secondary)
                    case let .failed(message):
                        Button {
                            showPreparationError = true
                        } label: {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.primary)
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
                .tint(.gray)
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

