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
    @State private var needsLicense = false
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
            if let selectedAccount {
                Button("Retry") { begin(accountID: selectedAccount) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Free License Required", isPresented: $needsLicense) {
            Button("Acquire Free License & Download") {
                guard let selectedAccount else { return }
                begin(accountID: selectedAccount, acquireFreeLicense: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add this free app to the selected account, then start downloading it.")
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

    private func begin(accountID: String, acquireFreeLicense: Bool = false) {
        guard !requesting else { return }
        selectedAccount = accountID
        requesting = true
        Task {
            defer { requesting = false }
            do {
                if acquireFreeLicense {
                    // Never silently acquire a license or purchase a paid app.
                    guard package.software.price == 0 else { return }
                    try await store.withAccount(id: accountID) { account in
                        try await ApplePackage.Authenticator.rotatePasswordToken(for: &account.account)
                        try await ApplePackage.Purchase.purchase(account: &account.account, app: package.software)
                    }
                }
                try await downloads.startDownload(for: package, accountID: accountID)
            } catch {
                if case ApplePackageError.licenseRequired = error, package.software.price == 0 {
                    needsLicense = true
                } else {
                    let networkError = error as NSError
                    errorMessage = networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorTimedOut
                        ? "The App Store download request timed out. Please retry. If this happens again, check Settings > Logs for the failed endpoint."
                        : error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
