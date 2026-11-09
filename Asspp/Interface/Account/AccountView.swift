//
//  AccountView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

struct AccountView: View {
    @State private var vm = AppStore.this
    @State private var addAccount = false
    @State private var selectedID: AppStore.UserAccount.ID?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    #if os(macOS)
        private var macOSBody: some View {
            NavigationStack(path: $navigationPath) {
                Group {
                    if vm.accounts.isEmpty {
                        ContentUnavailableView(
                            label: {
                                Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                            },
                            description: {
                                Text("Add an Apple ID to start downloading IPA packages.")
                            },
                            actions: {
                                Button("Add Account") { addAccount.toggle() }
                            },
                        )
                        .padding()
                    } else {
                        accountsTable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                    AccountDetailView(accountId: id)
                }
                .navigationTitle("Accounts")
                .toolbar { macToolbar }
            }
            .task(id: vm.accounts.map(\.id).joined(separator: "|")) {
                vm.prepareDownloads()
            }
            .sheet(isPresented: $addAccount) {
                AddAccountView()
                    .frame(minWidth: 480, idealWidth: 520, minHeight: 340, idealHeight: 380)
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }

        private var accountsTable: some View {
            Table(vm.accounts, selection: $selectedID) {
                TableColumn("Email") { account in
                    Text(account.account.email)
                        .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 240, ideal: 400, max: .infinity)

                TableColumn("Region") { account in
                    Text(account.account.store)
                }
                .width(min: 72, ideal: 88, max: 100)

                TableColumn("Storefront") { account in
                    Text(ApplePackage.Configuration.countryCode(for: account.account.store) ?? String(localized: "Unknown"))
                }
                .width(min: 56, ideal: 64, max: 80)

                TableColumn("") { account in
                    Button {
                        navigationPath.append(account.id)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .width(32)
            }
            .contextMenu(forSelectionType: AppStore.UserAccount.ID.self) { ids in
                if let id = ids.first {
                    Button("View Details") {
                        navigationPath.append(id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var footer: some View {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                Text("Accounts are stored securely in your Keychain and can be removed at any time from the detail view.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        @ToolbarContentBuilder
        private var macToolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAccount.toggle()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
    #endif

    #if !os(macOS)
        private var iOSBody: some View {
            NavigationStack(path: $navigationPath) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AssppScreenHeader(
                            eyebrow: "VELO  /  YOUR LIBRARY",
                            title: "Accounts",
                            subtitle: "Connect your App Store account to discover and download your apps.",
                            symbol: "person.crop.circle.badge.checkmark"
                        )

                        HStack {
                            Text("CONNECTED ACCOUNTS")
                                .font(.caption.bold())
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.58))
                            Spacer()
                            Text("\(vm.accounts.count)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(AssppTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AssppTheme.accent.opacity(0.11), in: Capsule())
                        }

                        if vm.accounts.isEmpty {
                            AssppCard {
                                VStack(alignment: .leading, spacing: 17) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 36, weight: .light))
                                        .foregroundStyle(AssppTheme.accent)
                                    Text("Start with your Apple Account")
                                        .font(.title3.bold())
                                    Text("Add an account once to download the IPA files already available to you in the App Store.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button { addAccount = true } label: {
                                        Label("Add Apple Account", systemImage: "plus.circle.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AssppTheme.accent)
                                }
                            }
                        } else {
                            ForEach(vm.accounts) { account in
                                NavigationLink(value: account.id) {
                                    AssppCard {
                                        HStack(spacing: 13) {
                                            Image(systemName: "person.crop.circle.fill")
                                                .font(.system(size: 30))
                                                .foregroundStyle(AssppTheme.accent)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(account.account.email)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(1)
                                                    .foregroundStyle(.white)
                                                    .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                                                Text("Storefront · \(ApplePackage.Configuration.countryCode(for: account.account.store) ?? account.account.store)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 2)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Button { addAccount = true } label: {
                                Label("Add another account", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
                .background(AssppTheme.background)
                .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                    AccountDetailView(accountId: id)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem {
                        Button {
                            addAccount.toggle()
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                    }
                }
            }
            .task(id: vm.accounts.map(\.id).joined(separator: "|")) {
                vm.prepareDownloads()
            }
            .sheet(isPresented: $addAccount) {
                NavigationStack {
                    AddAccountView()
                }
            }
        }
    #endif
}
