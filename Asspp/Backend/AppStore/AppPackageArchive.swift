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
        // Prior commerce responses could return stale versions; this new
        // cache stores only Info.plist verified labels.
        _versionItems = Persist(key: "\(packageIdentifier).ipaVerifiedVersionsV2", defaultValue: [:])
        _versionIdentifiers = Persist(key: "\(packageIdentifier).versionNumbers", defaultValue: [])
    }

    /// Paints every label that was already verified for this app, regardless of
    /// which Apple Account or storefront resolved it. The list is readable
    /// before any network request and stays readable when Apple denies a
    /// refresh.
    func hydrateCachedLabels() {
        let identifiers = versionIdentifiers
        guard !identifiers.isEmpty else { return }
        let appID = package.software.id
        let platform = platformKey
        Task {
            let cached = await VersionLabelStore.shared.cachedLabels(
                appID: appID, platform: platform, externalVersionIDs: identifiers)
            guard !cached.isEmpty else { return }
            var items = self.versionItems
            var changed = false
            for (identifier, label) in cached where items[identifier] == nil {
                items[identifier] = VersionMetadata(
                    displayVersion: label.version,
                    releaseDate: label.releaseDate ?? .distantPast,
                )
                changed = true
            }
            if changed { self.versionItems = items }
        }
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
        // The opaque Apple build identifier is only ever used as an internal
        // handle: it names the on-disk package directory and is part of the
        // download identity. It is never rendered as a version anywhere in the
        // interface, and it is never written into exported iTunesMetadata
        // because the real version replaces it from the validated ticket.
        pkg.software.version = versionItems[externalVersion]?.displayVersion ?? externalVersion
        pkg.externalVersionID = externalVersion
        return pkg
    }

    /// Apple's platform string is part of the version-label cache key. A tvOS
    /// build and an iOS build of the same app carry different identifiers.
    private var platformKey: String {
        (package.entityType ?? .iPhone).rawValue
    }

    /// A denial affects the whole Apple session, not one historical row. Keep
    /// every real identifier visible and stop hammering the rejected endpoint.
    /// Returns true when the caller should stop the current batch.
    private func handleMetadataDenial(_ error: Error) -> Bool {
        guard let failure = error as? StoreDownloadError else { return false }
        let accessDenied: Bool
        switch failure {
        case .response(403), .emptyResponse(403): accessDenied = true
        default: accessDenied = false
        }
        guard accessDenied else { return false }
        unavailableVersionIDs.formUnion(versionIdentifiers)
        self.error = error.localizedDescription
        logger.info("Historical metadata access denied; preserved all cached IDs")
        return true
    }

    /// A refresh must never erase valid versions just because Apple's current
    /// endpoint replies with 403. Keep the last successful authenticated list
    /// until another confirmed list replaces or extends it.
    func refreshVersionHistory(_ completion: (() async -> Void)? = nil) {
        guard !loading else { return }
        error = nil
        unavailableVersionIDs.removeAll()
        populateVersionIdentifiers(completion)
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
                    do {
                        return try await StoreDownloadService.versions(
                            account: &userAccount.account, package: requestedPackage)
                    } catch ApplePackageError.licenseRequired {
                        // Opening history authorizes a FREE App Store license only.
                        // Never purchase a paid app or automatically accept account terms.
                        guard FreeLicensePolicy.shouldAcquire(price: requestedPackage.software.price) else {
                            throw ApplePackageError.licenseRequired
                        }
                        logger.info("Version history: free license missing, acquiring before reloading versions")
                        do {
                            try await ApplePackage.Purchase.purchase(
                                account: &userAccount.account, app: requestedPackage.software)
                        } catch {
                            if FreeLicensePolicy.isExpiredToken(error.localizedDescription) {
                                try await ApplePackage.Authenticator.rotatePasswordToken(
                                    for: &userAccount.account)
                                try await ApplePackage.Purchase.purchase(
                                    account: &userAccount.account, app: requestedPackage.software)
                            } else if !FreeLicensePolicy.isAlreadyOwned(error.localizedDescription) {
                                throw error
                            }
                        }
                        // Request history once after license acquisition; do not
                        // repeatedly issue purchase requests on network errors.
                        return try await StoreDownloadService.versions(
                            account: &userAccount.account, package: requestedPackage)
                    }
                }
                var seen = Set<String>()
                // Merge only real IDs returned by Apple or previously verified
                // and persisted for this app, platform and store. Never add
                // placeholders; the old list remains usable on HTTP 403.
                self.versionIdentifiers = (Array(versions.reversed()) + self.versionIdentifiers)
                    .filter { seen.insert($0).inserted }
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

    /// Resolves display labels for a batch of historical builds.
    ///
    /// Two distinct costs are kept apart on purpose:
    ///  * the signed-asset lookup (cheap ticket, but shares the mutable Apple
    ///    account cookie jar, so it must stay serialized), and
    ///  * the Info.plist read (several HTTP Range requests per build, fully
    ///    independent of the account, so it runs concurrently).
    ///
    /// Previously every build paid both costs in sequence, which is why a long
    /// history list felt like it barely moved.
    func populateNextVersionItems(count: Int = 4) {
        guard let accountIdentifier, !loading, !isVersionItemsFullyLoaded else { return }
        loading = true
        error = nil

        Task {
            let appID = self.package.software.id
            let platform = self.platformKey
            let bundleID = self.package.software.bundleID
            let requestedPackage = self.package

            // Anything verified before is shown immediately and costs no network.
            let cached = await VersionLabelStore.shared.cachedLabels(
                appID: appID, platform: platform, externalVersionIDs: self.versionIdentifiers)
            if !cached.isEmpty {
                var items = self.versionItems
                var changed = false
                for (identifier, label) in cached where items[identifier] == nil {
                    items[identifier] = VersionMetadata(
                        displayVersion: label.version,
                        releaseDate: label.releaseDate ?? .distantPast,
                    )
                    changed = true
                }
                if changed { self.versionItems = items }
            }

            // Serialized: signed-asset lookups mutate the account state.
            var assets: [(String, URL)] = []
            for _ in 0 ..< count {
                guard let version = self.versionIdentifiers.first(where: {
                    self.versionItems[$0] == nil && !self.unavailableVersionIDs.contains($0)
                }) else { break }
                do {
                    let asset = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                        try await StoreDownloadService.versionAsset(account: &userAccount.account,
                                                                    package: requestedPackage,
                                                                    versionID: version)
                    }
                    assets.append((version, asset))
                } catch {
                    if self.handleMetadataDenial(error) { break }
                    // Preserve the identifier as a selectable version even when
                    // its display label cannot be resolved.
                    self.unavailableVersionIDs.insert(version)
                    logger.info("Version metadata unavailable for one historical entry; continuing the remaining entries")
                }
            }

            let resolved = await Self.resolveLabels(assets: assets, bundleID: bundleID)

            if !resolved.isEmpty {
                var items = self.versionItems
                for (identifier, version, date) in resolved {
                    items[identifier] = VersionMetadata(
                        displayVersion: version,
                        releaseDate: date ?? .distantPast,
                    )
                }
                self.versionItems = items
            }
            for (identifier, _, _) in resolved {
                self.unavailableVersionIDs.remove(identifier)
            }
            for (identifier, version, date) in resolved {
                await VersionLabelStore.shared.store(
                    appID: appID, platform: platform, externalVersionID: identifier,
                    version: version, releaseDate: date,
                )
            }

            self.loading = false
        }
    }

    /// Concurrent Info.plist reads with a bounded window. Apple tolerates a few
    /// parallel partial reads but throttles bursts, so the window is explicit
    /// rather than "one task per version".
    nonisolated private static func resolveLabels(
        assets: [(String, URL)], bundleID: String
    ) async -> [(String, String, Date?)] {
        guard !assets.isEmpty else { return [] }
        let limit = max(1, VersionLabelStore.maximumConcurrentResolutions)
        return await withTaskGroup(of: (String, String, Date?).self) { group in
            var results: [(String, String, Date?)] = []
            var index = 0
            func submit(_ group: inout TaskGroup<(String, String, Date?)>) {
                guard index < assets.count else { return }
                let (identifier, url) = assets[index]
                index += 1
                group.addTask {
                    guard let info = try? await StoreDownloadService.versionMetadataFromAsset(
                        url, bundleID: bundleID
                    ) else { return (identifier, "", nil) }
                    return (identifier, info.displayVersion, info.releaseDate)
                }
            }
            while index < assets.count, index < limit {
                submit(&group)
            }
            while let result = await group.next() {
                // An empty label means this build could not be verified; it is
                // reported as unavailable rather than given a fabricated name.
                if !result.1.isEmpty { results.append(result) }
                submit(&group)
            }
            return results
        }
    }

    func populateVersionItem(for versionID: String) {
        guard let accountIdentifier, !loading, versionIdentifiers.contains(versionID), versionItems[versionID] == nil else { return }
        loading = true
        error = nil

        Task {
            do {
                let requestedPackage = self.package
                let asset = try await self.withLockedAccount(id: accountIdentifier) { userAccount in
                    try await StoreDownloadService.versionAsset(account: &userAccount.account,
                                                                package: requestedPackage, versionID: versionID)
                }
                let metadata = try await StoreDownloadService.versionMetadataFromAsset(
                    asset, bundleID: requestedPackage.software.bundleID)
                self.versionItems[versionID] = metadata
                await VersionLabelStore.shared.store(
                    appID: requestedPackage.software.id, platform: self.platformKey,
                    externalVersionID: versionID, version: metadata.displayVersion,
                    releaseDate: metadata.releaseDate,
                )
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
