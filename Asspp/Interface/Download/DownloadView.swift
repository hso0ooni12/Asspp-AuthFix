//
//  DownloadView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI
struct DownloadView: View {
    @State private var vm = Downloads.this
    @State private var selectedFilter: DownloadFilter = .all

    private enum DownloadFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case ready = "Ready"
        var id: Self { self }
    }

    private var activeManifests: [PackageManifest] {
        vm.manifests.filter { !$0.completed }
    }

    private var readyManifests: [PackageManifest] {
        vm.manifests.filter(\.completed)
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

            if (selectedFilter == .all || selectedFilter == .active) && !vm.pendingPreparations.isEmpty {
                ForEach(Array(vm.pendingPreparations.keys).sorted(by: { $0.bundleID < $1.bundleID }), id: \.self) { key in
                    if let item = vm.pendingPreparations[key] {
                        HStack(spacing: 12) {
                            ProgressView().tint(AssppTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.appName).font(.subheadline.weight(.medium))
                                Text(item.statusText)
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
            if selectedFilter != .all &&
                ((selectedFilter == .active && activeManifests.isEmpty && vm.pendingPreparations.isEmpty) ||
                 (selectedFilter == .ready && readyManifests.isEmpty)) {
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
        PackageManifestRow(manifest: req) {
            deleteImmediately(id: req.id)
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
            vm.delete(request: request)
        }
    }
}

private struct PackageManifestRow: View {
    let manifest: PackageManifest
    let onDelete: () -> Void
    @State private var vm = Downloads.this
    @State private var showDetails = false

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
                    ShareLink(item: manifest.targetLocation) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                    .accessibilityLabel("Share Original IPA")
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
                    Label("Download Complete", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
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
                ShareLink(item: manifest.targetLocation) {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
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

