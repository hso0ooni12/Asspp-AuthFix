import ApplePackage
import SwiftUI

/// A sibling of the details link, so Download never opens the product page.
struct QuickDownloadButton: View {
    let package: AppStore.AppPackage
    let region: String

    @State private var store = AppStore.this
    @State private var downloads = Downloads.this
    @State private var requesting = false
    @State private var choosingAccount = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var selectedAccount: String?

    private var accounts: [AppStore.UserAccount] { store.eligibleAccounts(for: region) }
    private var preferredAccountKey: String { "Velo.PreferredAccount.\(region)" }

    private var pendingPreparation: DownloadPreparationStatus? {
        downloads.pendingPreparations.first(where: {
            $0.key.bundleID == package.software.bundleID &&
                $0.key.version == package.externalVersionID
        })?.value
    }

    var body: some View {
        Group {
            if let request = downloads.downloadRequest(forArchive: package) {
                NavigationLink(value: request) {
                    Group {
                        if request.completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(AssppTheme.accent.opacity(0.18), lineWidth: 4)
                                Circle()
                                    .trim(from: 0, to: min(max(request.state.percent, 0), 1))
                                    .stroke(AssppTheme.accent,
                                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                if request.state.status == .pending && request.state.percent == 0 {
                                    ProgressView()
                                        .tint(AssppTheme.accent)
                                        .scaleEffect(0.7)
                                } else {
                                    Text("\(Int(min(max(request.state.percent, 0), 1) * 100))%")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(AssppTheme.accent)
                                }
                            }
                            .frame(width: 35, height: 35)
                        }
                    }
                    .frame(width: 62, height: 40)
                }
                .accessibilityLabel(request.completed ? "Download complete" :
                    "Downloading, \(Int(request.state.percent * 100)) percent. Show download")
                .buttonStyle(.bordered)
            } else if let pendingPreparation {
                HStack(spacing: 5) {
                    ProgressView().tint(AssppTheme.accent).controlSize(.mini)
                    Text("Preparing")
                        .font(.caption2.bold())
                }
                .frame(minWidth: 80, minHeight: 38)
                .accessibilityLabel(pendingPreparation.stage.rawValue)
            } else {
                Button(action: selectAccount) {
                    Group {
                        if requesting {
                            ProgressView().tint(AssppTheme.accent)
                        } else {
                            Label("Get", systemImage: "arrow.down")
                                .font(.subheadline.bold())
                        }
                    }
                    .frame(minWidth: 48, minHeight: 24)
                }
                .buttonStyle(.bordered)
                .tint(AssppTheme.accent)
                .disabled(requesting)
                .accessibilityLabel(requesting ? "Preparing download" : "Download IPA")
                .contextMenu {
                    if accounts.count > 1 {
                        ForEach(accounts) { account in
                            Button(store.demoMode ? "Apple Account" : account.account.email) {
                                begin(accountID: account.id)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Download with", isPresented: $choosingAccount, titleVisibility: .visible) {
            ForEach(accounts) { account in
                Button(store.demoMode ? "Apple Account" : account.account.email) {
                    begin(accountID: account.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Download", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func selectAccount() {
        guard !requesting else { return }
        if let preferred = UserDefaults.standard.string(forKey: preferredAccountKey),
           accounts.contains(where: { $0.id == preferred }) {
            begin(accountID: preferred)
        } else if accounts.count == 1, let account = accounts.first {
            begin(accountID: account.id)
        } else if accounts.isEmpty {
            errorMessage = "Add an Apple Account for \(region) in Accounts to download this app."
            showingError = true
        } else {
            choosingAccount = true
        }
    }

    private func begin(accountID: String) {
        guard !requesting else { return }
        selectedAccount = accountID
        UserDefaults.standard.set(accountID, forKey: preferredAccountKey)
        requesting = true
        Task {
            defer { requesting = false }
            do {
                try await downloads.startDownload(for: package, accountID: accountID)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

