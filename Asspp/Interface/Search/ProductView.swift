//
//  ProductView.swift
//  Velo — App Store-inspired product details
//

import ApplePackage
import ButtonKit
import Kingfisher
import SwiftUI

struct ProductView: View {
    @State private var archive: AppPackageArchive
    @Binding var navigationPath: NavigationPath

    init(archive: AppStore.AppPackage, region: String, navigationPath: Binding<NavigationPath>) {
        _archive = State(initialValue: AppPackageArchive(accountID: nil, region: region, package: archive))
        _navigationPath = navigationPath
    }

    @State private var vm = AppStore.this
    @State private var dvm = Downloads.this
    @State private var selection: AppStore.UserAccount.ID = .init()
    @State private var hint: Hint?
    @State private var requestingDownload = false
    @State private var showError = false
    @State private var showFullDescription = false

    var region: String { archive.region }

    var eligibleAccounts: [AppStore.UserAccount] {
        vm.eligibleAccounts(for: region)
    }

    var account: AppStore.UserAccount? {
        vm.accounts.first { $0.id == selection }
    }

    private var software: ApplePackage.Software { archive.package.software }

    private var fileSize: String {
        guard let bytes = software.fileSizeBytes.flatMap(Int64.init) else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                stats
                screenshots
                about
                if let notes = software.releaseNotes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        sectionTitle("What's New")
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                versionHistory
                details
                accountSelector
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 28)
        }
        .background(AssppTheme.background)
        .navigationTitle(software.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .onAppear {
            selection = eligibleAccounts.first?.id ?? .init()
            vm.prepareDownloads(region: region, accountID: selection)
        }
        .onChange(of: selection) { _, value in
            vm.prepareDownloads(region: region, accountID: value)
        }
        .alert("Download", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hint?.message ?? "Unable to start download.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            KFImage(URL(string: software.artworkUrl))
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 112, height: 112)))
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(AssppTheme.separator.opacity(0.3), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(software.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(software.sellerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    downloadButton
                    if software.price == 0 {
                        Text("Free")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let formatted = software.formattedPrice {
                        Text(formatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if let request = dvm.downloadRequest(forArchive: archive.package) {
            NavigationLink(value: request) {
                Text(request.completed ? "OPEN" : "VIEW")
                    .frame(minWidth: 52)
            }
            .buttonStyle(VeloPillButtonStyle(prominent: true))
        } else {
            Button {
                guard let account, !requestingDownload else { return }
                requestingDownload = true
                Task {
                    defer { requestingDownload = false }
                    do {
                        try await dvm.startDownload(for: archive.package, accountID: account.id)
                        hint = Hint(message: String(localized: "Download Requested"), color: nil)
                        if let request = dvm.downloadRequest(forArchive: archive.package) {
                            navigationPath.append(request)
                        }
                    } catch {
                        hint = Hint(message: error.localizedDescription, color: .red)
                        showError = true
                    }
                }
            } label: {
                if requestingDownload {
                    ProgressView().tint(.white).frame(minWidth: 52)
                } else {
                    Text("GET").frame(minWidth: 52)
                }
            }
            .buttonStyle(VeloPillButtonStyle(prominent: true))
            .disabled(account == nil || requestingDownload)
            .accessibilityLabel("Download IPA")
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            statItem(label: "RATINGS",
                     value: software.userRatingCount > 0
                        ? String(format: "%.1f", software.averageUserRating) : "—",
                     detail: software.userRatingCount > 0
                        ? "\(software.userRatingCount.formatted()) reviews" : "No ratings")
            statDivider
            statItem(label: "CATEGORY",
                     value: software.primaryGenreName.isEmpty ? "—" : software.primaryGenreName,
                     detail: "App Store")
            statDivider
            statItem(label: "SIZE", value: fileSize, detail: "Download")
            statDivider
            statItem(label: "REQUIRES",
                     value: "iOS \(software.minimumOsVersion)+",
                     detail: "Compatibility")
        }
        .padding(.vertical, 15)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(AssppTheme.separator.opacity(0.4))
            .frame(width: 0.5, height: 58)
            .padding(.horizontal, 3)
    }

    private func statItem(label: String, value: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var screenshots: some View {
        if !software.screenshotUrls.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Preview")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(software.screenshotUrls.prefix(8), id: \.self) { address in
                            KFImage(URL(string: address))
                                .setProcessor(DownsamplingImageProcessor(
                                    size: CGSize(width: 260, height: 460)))
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(AssppTheme.elevated)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 210, height: 365)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contentMargins(.trailing, 2)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("About This App")
            Text(software.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(showFullDescription ? nil : 4)
            if !showFullDescription && software.description.count > 170 {
                Button("More") { showFullDescription = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var versionHistory: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Version History")
            NavigationLink {
                LazyView(ProductHistoryView(vm: AppPackageArchive(
                    accountID: selection, region: region, package: archive.package)))
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(software.version)")
                            .font(.subheadline.weight(.semibold))
                        Text("View and download previous versions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(account == nil)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Information")
            VStack(spacing: 0) {
                detailRow("Developer", software.sellerName)
                Divider()
                detailRow("Category", software.primaryGenreName)
                Divider()
                detailRow("Version", software.version)
                Divider()
                detailRow("Bundle ID", software.bundleID)
                Divider()
                detailRow("Price", software.formattedPrice ?? "N/A")
            }
            .padding(.horizontal, 14)
            .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private func detailRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .foregroundStyle(.primary)
                .frame(width: 87, alignment: .leading)
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

    private var accountSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Apple Account")
            if eligibleAccounts.isEmpty {
                Text("Add an Apple Account for \(region) in Accounts to download this app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Download with", selection: $selection) {
                    ForEach(eligibleAccounts) { account in
                        Text(account.account.email)
                            .tag(account.id)
                    }
                }
                .pickerStyle(.menu)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            }
            Text("Free licenses are requested automatically. Paid purchases are never initiated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ label: String) -> some View {
        Text(label).font(.title3.bold())
    }
}

extension AppStore.AppPackage {
    var displaySupportedDevicesIcon: String {
        "iphone"
    }
}

/// Constructs expensive historical metadata only after navigation.
struct LazyView<Content: View>: View {
    private let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content { build() }
}
