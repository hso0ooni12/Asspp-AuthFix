//
//  PackageView.swift
//  Velo — App Store-style download details
//

import ApplePackage
import ButtonKit
import Kingfisher
import SwiftUI
#if os(iOS)
import ZIPFoundation
import Security
#endif

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
#endif

struct PackageView: View {
    @State var pkg: PackageManifest

    var archive: AppStore.AppPackage { pkg.package }
    var url: URL { pkg.targetLocation }

    @Environment(\.dismiss) var dismiss
    #if os(iOS)
        @State private var installer: Installer?
        @State private var error: String = ""
    #endif
    #if os(macOS)
        @State private var copied = false
    #endif

    @State private var vm = AppStore.this
    @State private var downloads = Downloads.this

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero
                if pkg.completed {
                    completedActions
                } else {
                    transferActions
                }
                packageInformation
                accountInformation
                advancedTools
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 30)
        }
        .background(AssppTheme.background)
        .tint(AssppTheme.accent)
        .navigationTitle("Download Details")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            KFImage(URL(string: archive.software.artworkUrl))
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 100, height: 100)))
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 23))
            VStack(alignment: .leading, spacing: 6) {
                Text(archive.software.name)
                    .font(.title2.bold())
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(archive.software.sellerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Version \(archive.software.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var completedActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Download Complete")
            #if os(iOS)
                ShareLink(item: url) {
                    Label("Share Original IPA", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VeloPillButtonStyle(prominent: true))

                DisclosureGroup("Installation options") {
                    VStack(alignment: .leading, spacing: 12) {
                        AsyncButton {
                            installer = try await Installer(archive: archive, path: url)
                        } label: {
                            Label("Install", systemImage: "square.and.arrow.down")
                        }
                        .disabledWhenLoading()
                        .sheet(item: $installer) {
                            installer?.destroy()
                            installer = nil
                        } content: {
                            InstallerView(installer: $0)
                        }
                        Button {
                            let newURL = temporaryDirectory
                                .appendingPathComponent("\(archive.software.bundleID)-\(archive.software.version)")
                                .appendingPathExtension("ipa")
                            try? FileManager.default.removeItem(at: newURL)
                            try? FileManager.default.copyItem(at: url, to: newURL)
                            AirDrop(items: [newURL])
                        } label: {
                            Label("Install via AirDrop", systemImage: "airplayaudio")
                        }
                        if !error.isEmpty {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 9)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #else
                DeviceCTLInstallSection(package: pkg)
            #endif
        }
    }

    private var transferActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Download")
            HStack(spacing: 10) {
                Text(pkg.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Text("\(Int(pkg.state.percent * 100))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            ProgressView(value: pkg.state.percent)
                .tint(AssppTheme.accent)
            HStack(spacing: 10) {
                ForEach(downloads.getAvailableActions(for: pkg).filter { $0 != .delete }, id: \.self) { action in
                    let label = downloads.getActionLabel(for: action)
                    Button {
                        downloads.performDownloadAction(for: pkg, action: action)
                    } label: {
                        Label(label.title, systemImage: label.systemImage)
                    }
                    .buttonStyle(VeloPillButtonStyle())
                }
            }
            if let error = pkg.state.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
    }

    private var packageInformation: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Information")
            VStack(spacing: 0) {
                detailRow("Bundle ID", archive.software.bundleID)
                Divider()
                detailRow("Version", archive.software.version)
                Divider()
                detailRow("Developer", archive.software.sellerName)
                if !archive.software.primaryGenreName.isEmpty {
                    Divider()
                    detailRow("Category", archive.software.primaryGenreName)
                }
                Divider()
                detailRow("Requires", "iOS \(archive.software.minimumOsVersion)+")
                if archive.software.userRatingCount > 0 {
                    Divider()
                    detailRow("Rating", String(format: "%.1f", archive.software.averageUserRating))
                }
            }
            .padding(.horizontal, 14)
            .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private var accountInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Account")
            Text(pkg.account.account.email)
                .font(.subheadline)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            Text("\(pkg.account.account.store) · \(ApplePackage.Configuration.countryCode(for: pkg.account.account.store) ?? String(localized: "Unknown"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("More")
            NavigationLink {
                FileListView(packageURL: pkg.targetLocation)
            } label: {
                Label("Browse IPA Contents", systemImage: "folder")
                    .font(.subheadline.weight(.medium))
            }
            #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            #endif
            Divider()
            Button(role: .destructive) {
                dismiss()
                Task { @MainActor in
                    await Task.yield()
                    downloads.performDownloadAction(for: pkg, action: .delete)
                }
            } label: {
                Label("Delete Download", systemImage: "trash")
                    .font(.subheadline)
            }
        }
        .padding(.top, 5)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: 86, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 13)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold())
    }
}
