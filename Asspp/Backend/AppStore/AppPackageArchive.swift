//
//  AppPackageArchive.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import Foundation
import OrderedCollections

@MainActor
@Observable
class AppPackageArchive {
    @ObservationIgnored
    let accountIdentifier: String?
    @ObservationIgnored
    let region: String

    var package: AppStore.AppPackage

    typealias VersionIdentifier = String
    @ObservationIgnored
    private var _versionIdentifiers: Persist<[VersionIdentifier]>

    var versionIdentifiers: [VersionIdentifier] {
        get {
            access(keyPath: \.versionIdentifiers)
            return _versionIdentifiers.wrappedValue
        }
        set {
            withMutation(keyPath: \.versionIdentifiers) {
                _versionIdentifiers.wrappedValue = newValue
            }
        }
    }

    @ObservationIgnored
    private var _versionItems: Persist<OrderedDictionary<VersionIdentifier, VersionMetadata>>

    var versionItems: OrderedDictionary<VersionIdentifier, VersionMetadata> {
        get {
            access(keyPath: \.versionItems)
            return _versionItems.wrappedValue
        }
        set {
            withMutation(keyPath: \.versionItems) {
                _versionItems.wrappedValue = newValue
            }
        }
    }

    var isVersionItemsFullyLoaded: Bool {
        versionIdentifiers.allSatisfy { versionItems[$0] != nil || unavailableVersionIDs.contains($0) }
    }

    /// A single historical build may no longer expose details on Apple's
    /// endpoint. Keep the rest of the history usable instead of getting stuck
    /// at the first missing entry.
    @ObservationIgnored
    private var unavailableVersionIDs: Set<String> = []

    var error: String?
    var loading = false
    var shouldDismiss = false

    init(accountID: String?, region: String, package: AppStore.AppPackage) {
        accountIdentifier = accountID
        self.region = region
        self.package = package

        let packageIdentifier = [package.id, package.software.bundleID.lowercased(), region, (package.entityType ?? .iPhone).rawValue]
            .joined()
            .lowercased()
        _versionItems = Persist(key: "\(packageIdentifier).versions", defaultValue: [:])
        _versionIdentifiers = Persist(key: "\(packageIdentifier).versionNumbers", defaultValue: [])
    }

    /// History lookups touch the same mutable account cookie jar as downloads.
    /// Avoid a background history refresh overwriting the account state of a
    /// concurrent download preparation.
    private func withLockedAccount<T>(id: String,
                                      _ body: (inout AppStore.UserAccount) async throws -> T) async throws -> T
    {
        await AccountDownloadGate.shared.acquire(id)
        defer { Task { await AccountDownloadGate.shared.release(id) } }
        return try await AppStore.this.withAccount(id: id, body)
    }

    func package(for externalVersion: String) -> AppStore.AppPackage? {
        guard versionIdentifiers.contains(externalVersion) else { return nil }
        var pkg = package
        pkg.software.version = versionItems[externalVersion]?.displayVersion ?? "ID \(externalVersion)"
        pkg.externalVersionID = externalVersion
        return pkg
    }

    func clearVersionItems() {
        assert(!loading)
        error = nil
        unavailableVersionIDs.removeAll()
        versionIdentifiers = []
        versionItems = [:]
    }

    func populateVersionIdentifiers(_ completion: (() async -> Void)? = nil) {
        guard let accountIdentifier, !loading else { return }
        let requestedPackage = package
        loading = true
        error = nil

        Task {
            do {
                let versions = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                    try await StoreDownloadService.versions(account: &userAccount.account, package: requestedPackage)
                }
                self.versionIdentifiers = Array(versions.reversed())
                self.unavailableVersionIDs.formIntersection(self.versionIdentifiers)
            } catch {
                if case .licenseRequired = error as? ApplePackageError {
                    self.shouldDismiss = true
                }
                self.error = error.localizedDescription
            }
            self.loading = false
            await completion?()
        }
    }

    func populateNextVersionItems(count: Int = 3) {
        guard let accountIdentifier, !loading, !isVersionItemsFullyLoaded else { return }
        loading = true
        error = nil

        Task {
            for _ in 0 ..< count {
                guard let version = self.versionIdentifiers.first(where: {
                    self.versionItems[$0] == nil && !self.unavailableVersionIDs.contains($0)
                }) else { break }
                let requestedPackage = self.package
                do {
                    let metadata = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                        try await StoreDownloadService.versionMetadata(account: &userAccount.account, package: requestedPackage, versionID: version)
                    }
                    self.versionItems[version] = metadata
                } catch {
                    // Preserve the ID as a selectable version even when
                    // its display date/name cannot be resolved.
                    self.unavailableVersionIDs.insert(version)
                    logger.info("Version metadata unavailable for one historical entry; continuing the remaining entries")
                }
            }
            self.loading = false
        }
    }

    func populateVersionItem(for versionID: String) {
        guard let accountIdentifier, !loading, versionIdentifiers.contains(versionID), versionItems[versionID] == nil else { return }
        loading = true
        error = nil

        Task {
            do {
                let requestedPackage = self.package
                let metadata = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                    try await StoreDownloadService.versionMetadata(account: &userAccount.account, package: requestedPackage, versionID: versionID)
                }
                self.versionItems[versionID] = metadata
            } catch {
                self.unavailableVersionIDs.insert(versionID)
                logger.info("Historical version details unavailable; version ID remains downloadable")
            }
            self.loading = false
        }
    }
}

extension AppPackageArchive {
    var version: String {
        package.software.version
    }

    var releaseDate: Date? {
        package.releaseDate
    }

    var releaseNotes: String? {
        package.software.releaseNotes
    }

    var formattedPrice: String? {
        package.software.formattedPrice
    }

    var price: Double? {
        package.software.price
    }

    var downloadOutput: DownloadOutput? {
        get { package.downloadOutput }
        set { package.downloadOutput = newValue }
    }
}
