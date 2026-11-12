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
    @State private var selectedFilter: DownloadFilter = .all

    private enum DownloadFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case ready = "Ready"
        case completed = "Prepared"
        var id: Self { self }
    }

    private var activeManifests: [PackageManifest] {
        vm.manifests.filter { !$0.completed }
    }

    private var preparedManifests: [PackageManifest] {
        vm.manifests.filter {
            guard $0.completed else { return false }
            if case .ready = decryptor.status(for: $0) { return true }
            return false
        }
    }

    private var readyManifests: [PackageManifest] {
        vm.manifests.filter { manifest in
            guard manifest.completed else { return false }
            if case .ready = decryptor.status(for: manifest) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Downloads")
        }
    }

    private var content: some View {
        List {
            Section {
                Picker("Downloads", selection: $selectedFilter) {
                    ForEach(DownloadFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 5)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

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

            if (selectedFilter == .all || selectedFilter == .active) && !vm.pendingPreparations.isEmpty {
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
            if (selectedFilter == .all || selectedFilter == .active) && !activeManifests.isEmpty {
                Section("Active") {
                    ForEach(activeManifests, id: \.id) { req in
                        manifestRow(req)
                    }
                }
            }
            if (selectedFilter == .all || selectedFilter == .ready) && !readyManifests.isEmpty {
                Section("Ready") {
                    ForEach(readyManifests, id: \.id) { req in
                        manifestRow(req)
                    }
                }
            }
            if (selectedFilter == .all || selectedFilter == .completed) && !preparedManifests.isEmpty {
                Section("Prepared") {
                    ForEach(preparedManifests, id: \.id) { req in
                        manifestRow(req)
                    }
                }
            }
            if selectedFilter != .all &&
                ((selectedFilter == .active && activeManifests.isEmpty && vm.pendingPreparations.isEmpty) ||
                 (selectedFilter == .ready && readyManifests.isEmpty) ||
                 (selectedFilter == .completed && preparedManifests.isEmpty)) {
                Text("Nothing here yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                NavigationLink(value: manifest) {
                    ArchivePreviewView(archive: manifest.package,
                                       preferredIconSize: 60, showsVersion: true)
                }
                .buttonStyle(.plain)

                switch manifest.state.status {
                case .completed:
                    Button {
                        decryptor.prepare(manifest)
                    } label: {
                        if decryptor.status(for: manifest) == .preparing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Decrypt")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .buttonStyle(VeloPillButtonStyle(prominent: true))
                    .disabled(decryptor.status(for: manifest) == .preparing)
                    .accessibilityLabel("Decrypt IPA")
                case .pending, .downloading:
                    Button {
                        vm.suspend(request: manifest)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                    .accessibilityLabel("Pause download")
                case .paused:
                    Button {
                        vm.resume(request: manifest)
                    } label: {
                        Image(systemName: "play.fill")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                    .accessibilityLabel("Resume download")
                case .failed:
                    Button {
                        vm.restart(request: manifest)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                    .accessibilityLabel("Retry download")
                }
            }

            if !manifest.completed {
                HStack(spacing: 8) {
                    Text(manifest.hint)
                        .font(.caption)
                        .foregroundStyle(manifest.state.error == nil ? Color.secondary : Color.red)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text("\(Int(manifest.state.percent * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: manifest.state.percent)
                    .tint(AssppTheme.accent)
            } else {
                HStack(spacing: 8) {
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
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    case .idle:
                        Label("Ready to Decrypt", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(manifest.package.software.version)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

