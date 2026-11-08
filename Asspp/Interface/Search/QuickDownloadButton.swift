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

    var body: some View {
        Group {
            if let request = downloads.downloadRequest(forArchive: package) {
                NavigationLink(value: request) {
                    Image(systemName: request.completed ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.title3)
                        .frame(width: 62, height: 40)
                }
                .accessibilityLabel("Show Download")
                .buttonStyle(.bordered)
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
        if accounts.count == 1, let account = accounts.first {
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
