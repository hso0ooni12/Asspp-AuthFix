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

    var verifiedVersionIDs: [VersionIdentifier] {
        let items = versionItems
        return versionIdentifiers.filter { identifier in
            guard let item = items[identifier] else { return false }
            return StoreDownloadProtocol.verifiedHistoryVersion(item.displayVersion, externalID: identifier) != nil
        }
    }

    var canLoadMoreVersions: Bool {
        accountIdentifier != nil && !loading && error == nil &&
            verifiedVersionIDs.count + unavailableVersionIDs.count < versionIdentifiers.count
    }

    var appStoreURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apps.apple.com"
        components.path = "/\(region.lowercased())/app/id\(package.software.id)"
        return components.url
    }

    private var unavailableVersionIDs: Set<String> = []

    var error: String?
    var loading = false

    init(accountID: String?, region: String, package: AppStore.AppPackage) {
        accountIdentifier = accountID
        self.region = region
        self.package = package

        let packageIdentifier = [package.id, package.software.bundleID.lowercased(), region, (package.entityType ?? .iPhone).rawValue]
            .joined()
            .lowercased()
        // Prior commerce responses could return stale versions; this new
        // cache stores only Info.plist verified labels.
        _versionItems = Persist(key: "\(packageIdentifier).ipaVerifiedVersionsV2", defaultValue: [:])
        _versionIdentifiers = Persist(key: "\(packageIdentifier).versionNumbers", defaultValue: [])
    }

    /// History lookups touch the same mutable account cookie jar as downloads.
    /// Avoid a background history refresh overwriting the account state of a
    /// concurrent download preparation.
    private func withLockedAccount<T>(id: String,
                                      _ body: (inout AppStore.UserAccount) async throws -> T) async throws -> T
    {
        await AccountDownloadGate.shared.acquire(id, interactive: false)
        defer { Task { await AccountDownloadGate.shared.release(id) } }
        try Task.checkCancellation()
        return try await AppStore.this.withAccount(id: id, body)
    }

    func package(for externalVersion: String) -> AppStore.AppPackage? {
        guard versionIdentifiers.contains(externalVersion), let metadata = versionItems[externalVersion],
              let version = StoreDownloadProtocol.verifiedHistoryVersion(metadata.displayVersion, externalID: externalVersion)
        else { return nil }
        var pkg = package
        pkg.software.version = version
        pkg.externalVersionID = externalVersion
        return pkg
    }

    /// A refresh must never erase valid versions just because Apple's current
    /// endpoint replies with 403. Keep the last successful authenticated list
    /// until another confirmed list replaces or extends it.
    func refreshVersionHistory() {
        guard !loading else { return }
        error = nil
        unavailableVersionIDs.removeAll()
        populateVersionIdentifiers()
    }

    func clearVersionItems() {
        assert(!loading)
        error = nil
        unavailableVersionIDs.removeAll()
        versionIdentifiers = []
        versionItems = [:]
    }

    func populateVersionIdentifiers() {
        guard let accountIdentifier, !loading else { return }
        let requestedPackage = package
        loading = true
        error = nil

        Task {
            do {
                let versions = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                    try await StoreDownloadService.versions(
                        account: &userAccount.account, package: requestedPackage)
                }
                var seen = Set<String>()
                // Merge only real IDs returned by Apple or previously verified
                // and persisted for this app, platform and store. Never add
                // placeholders; the old list remains usable on HTTP 403.
                self.versionIdentifiers = (Array(versions.reversed()) + self.versionIdentifiers)
                    .filter { seen.insert($0).inserted }
                self.unavailableVersionIDs.formIntersection(self.versionIdentifiers)
            } catch {
                self.error = error.localizedDescription
            }
            self.loading = false
            self.populateNextVersionItems()
        }
    }

    func populateNextVersionItems() {
        guard let accountIdentifier, canLoadMoreVersions else { return }
        let excluded = unavailableVersionIDs.union(verifiedVersionIDs)
        let batch = StoreDownloadProtocol.historyBatch(versionIdentifiers, excluding: excluded, limit: 4)
        loading = true

        Task {
            defer { loading = false }
            let requestedPackage = package
            let bundleID = requestedPackage.software.bundleID
            let platform = requestedPackage.entityType == .appleTV ? "AppleTVOS" : "iPhoneOS"
            await withTaskGroup(of: (String, String?, Date?).self) { assets in
                for identifier in batch {
                    do {
                        let asset = try await withLockedAccount(id: accountIdentifier) { userAccount in
                            try await StoreDownloadService.versionAsset(account: &userAccount.account,
                                                                        package: requestedPackage, versionID: identifier)
                        }
                        assets.addTask {
                            do {
                                let details = try await StoreDownloadService.versionMetadataFromAsset(
                                    asset, bundleID: bundleID, platform: platform)
                                return (identifier, StoreDownloadProtocol.verifiedHistoryVersion(
                                    details.displayVersion, externalID: identifier), details.releaseDate)
                            } catch {
                                logger.info("Version asset metadata unavailable: \(StoreDiagnostics.errorSummary(error))")
                                return (identifier, nil, nil)
                            }
                        }
                    } catch StoreDownloadError.response(403) {
                        self.error = StoreDownloadError.response(403).localizedDescription
                        break
                    } catch StoreDownloadError.emptyResponse(403) {
                        self.error = StoreDownloadError.emptyResponse(403).localizedDescription
                        break
                    } catch {
                        unavailableVersionIDs.insert(identifier)
                        logger.info("Version ticket unavailable: \(StoreDiagnostics.errorSummary(error))")
                    }
                }
                for await (identifier, version, date) in assets {
                    if let version {
                        versionItems[identifier] = VersionMetadata(
                            displayVersion: version, releaseDate: date ?? .distantPast)
                    } else {
                        unavailableVersionIDs.insert(identifier)
                    }
                }
            }
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
