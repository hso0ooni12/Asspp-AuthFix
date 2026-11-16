//
//  VersionLabelStore.swift
//  Asspp
//
//  Cross-account cache that maps Apple's opaque external version identifiers
//  (for example 863927451) onto the human-readable version string that is
//  embedded in the signed IPA (for example 5.7.1).
//
//  Why this exists: Apple's version-history endpoint only ever returns numeric
//  build identifiers. The only trustworthy label is the CFBundleShortVersionString
//  inside the signed asset's main Info.plist, and reading it costs a handful of
//  HTTP Range requests per build. Those requests do not depend on the Apple
//  Account, the storefront, or the purchase, so a resolved label is valid for
//  every account and can be cached permanently.
//
//  Consequence: a build that has been resolved once is displayed immediately,
//  even offline, and a version identifier is never presented to the user as a
//  version number.
//

import Foundation

actor VersionLabelStore {
    static let shared = VersionLabelStore()

    /// Apple throttles bursts of metadata reads. Four concurrent partial reads
    /// is roughly the point where history population stops feeling serial and
    /// still stays far below the point where Apple starts answering 403/429.
    static let maximumConcurrentResolutions = 4

    /// A build identifier is never reused by Apple, so entries never expire.
    /// The cap only stops unbounded growth for a library-type account.
    static let maximumEntries = 5000

    struct Label: Codable, Sendable, Equatable {
        let version: String
        let releaseDate: Date?
        let resolvedAt: Date
    }

    private var labels: [String: Label] = [:]
    private var isLoaded = false
    private var hasPendingWrite = false

    /// Platform is part of the key: the same app can carry a different build
    /// identifier per platform and one label must never be shown for the other.
    static func identifier(appID: Int64, platform: String, externalVersionID: String) -> String {
        "\(appID)|\(platform.lowercased())|\(externalVersionID)"
    }

    private static var cacheFileURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let container = directory.appendingPathComponent("VeloVersionLabels", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent("labels.json")
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let url = Self.cacheFileURL, let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([String: Label].self, from: data) {
            labels = decoded
        }
    }

    private func scheduleWrite() {
        hasPendingWrite = true
        // Coalesce: a batch of 20 resolutions writes the file once.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.flushIfNeeded()
        }
    }

    private func flushIfNeeded() {
        guard hasPendingWrite, let url = Self.cacheFileURL else { return }
        hasPendingWrite = false
        if labels.count > Self.maximumEntries {
            // Keep the most recently resolved entries.
            let trimmed = labels
                .sorted { $0.value.resolvedAt > $1.value.resolvedAt }
                .prefix(Self.maximumEntries)
            labels = Dictionary(uniqueKeysWithValues: Array(trimmed))
        }
        guard let data = try? JSONEncoder().encode(labels) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Non-blocking cache read used to paint a history list instantly.
    func cachedLabels(appID: Int64, platform: String, externalVersionIDs: [String]) -> [String: Label] {
        loadIfNeeded()
        var result: [String: Label] = [:]
        for identifier in externalVersionIDs {
            let key = Self.identifier(appID: appID, platform: platform, externalVersionID: identifier)
            if let label = labels[key] {
                result[identifier] = label
            }
        }
        return result
    }

    func store(appID: Int64, platform: String, externalVersionID: String, version: String, releaseDate: Date?) {
        loadIfNeeded()
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never cache an empty label: an empty string must not compete with a
        // later successful resolution.
        guard !trimmed.isEmpty, !Self.looksLikeBuildIdentifier(trimmed) else { return }
        let key = Self.identifier(appID: appID, platform: platform, externalVersionID: externalVersionID)
        labels[key] = Label(version: trimmed, releaseDate: releaseDate, resolvedAt: .init())
        scheduleWrite()
    }

    /// Defence in depth: a resolved label is only ever used when it looks like a
    /// version string. A numeric-only value is a build identifier, not a
    /// version, and must never reach the interface.
    static func looksLikeBuildIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let digits = trimmed.allSatisfy { $0.isASCII && $0.isNumber }
        // A long all-digits string is a build identifier. A short one such as
        // "27" is still a legitimate marketing version, so require both a
        // numeric body and enough length to be an opaque identifier.
        return digits && trimmed.count >= 7
    }

    /// Writes any coalesced changes immediately. Used when the app backgrounds
    /// so a resolution is never lost after the debounce window.
    func flush() {
        flushIfNeeded()
    }
}
