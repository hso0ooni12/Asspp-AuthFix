//
//  Downloads.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
@preconcurrency import Digger
import Foundation
import Logging

@Observable
@MainActor
class Downloads {
    static let this = Downloads()

    @ObservationIgnored
    private var _manifests = Persist<[PackageManifest]>(key: "DownloadRequests", defaultValue: [])

    @ObservationIgnored
    private var lastProgressUpdates: [UUID: CFAbsoluteTime] = [:]

    /// Manifest IDs whose Digger callbacks are already attached, so a
    /// pause/resume cycle does not register a second completion handler (which
    /// would run finalize() twice and destroy the downloaded bytes).
    @ObservationIgnored
    private var registeredCallbacks: Set<UUID> = []

    /// Limit transfers to two independent IPAs. Apple's metadata/auth requests
    /// are serialized per account separately; byte transfers can overlap.
    @ObservationIgnored private var activeTransferIDs: Set<UUID> = []
    @ObservationIgnored private var queuedTransferIDs: [UUID] = []
    @ObservationIgnored private var finalizingIDs: Set<UUID> = []

    /// Share one metadata request when multiple entry points request the same
    /// account, app, platform and version at once.
    @ObservationIgnored
    var pendingDownloadRequests: [DownloadRequestIdentity: Task<Void, Error>] = [:]

    /// Observable metadata/license requests become visible immediately, even
    /// before Apple returns a signed IPA URL and a PackageManifest can exist.
    var pendingPreparations: [DownloadRequestIdentity: DownloadPreparationStatus] = [:]

    private static let speedFormatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file
        return fmt
    }()

    var manifests: [PackageManifest] {
        get {
            access(keyPath: \.manifests)
            return _manifests.wrappedValue
        }
        set {
            withMutation(keyPath: \.manifests) {
                _manifests.wrappedValue = newValue
            }
        }
    }

    /// Stored, not computed: a computed property would read each manifest's
    /// `state`, so every download progress tick would invalidate the badge,
    /// sidebar, and AppDelegate observers and re-render the whole TabView.
    /// Refresh it only when a status actually transitions.
    private(set) var runningTaskCount: Int = 0

    var activeOperationCount: Int {
        runningTaskCount + pendingPreparations.count
    }

    private func refreshRunningTaskCount() {
        runningTaskCount = manifests.count(where: {
            $0.state.status == .pending || $0.state.status == .downloading
        })
    }

    private init() {
        for idx in manifests.indices {
            manifests[idx].state.resetIfNotCompleted()
        }
        refreshRunningTaskCount()
    }

    func saveManifests() {
        _manifests.save()
    }

    func downloadRequest(forArchive archive: AppStore.AppPackage) -> PackageManifest? {
        manifests.first { $0.package.id == archive.id && $0.package.externalVersionID == archive.externalVersionID }
    }

    func add(request: PackageManifest) -> PackageManifest {
        logger.info("adding download request \(request.id) - \(request.package.software.name)")
        manifests.removeAll { $0.id == request.id }
        manifests.append(request)
        return request
    }

    func suspend(request: PackageManifest) {
        logger.info("suspending download request id: \(request.id)")
        queuedTransferIDs.removeAll { $0 == request.id }
        if activeTransferIDs.contains(request.id) {
            DiggerManager.shared.stopTask(for: request.url)
            releaseTransferSlot(request.id)
        }
        request.state.resetIfNotCompleted()
        refreshRunningTaskCount()
        saveManifests()
    }

    func resume(request: PackageManifest) {
        logger.info("resuming download request id: \(request.id)")
        guard manifests.contains(where: { $0.id == request.id }) else { return }
        if !activeTransferIDs.contains(request.id) {
            if activeTransferIDs.count >= 2 {
                if !queuedTransferIDs.contains(request.id) {
                    queuedTransferIDs.append(request.id)
                }
                request.state.start()
                refreshRunningTaskCount()
                saveManifests()
                return
            }
            activeTransferIDs.insert(request.id)
            queuedTransferIDs.removeAll { $0 == request.id }
        }
        request.state.start()
        let seed = DiggerManager.shared.download(with: request.url)

        // Only attach callbacks once per manifest; a pause/resume cycle reuses
        // the existing Digger seed and must not stack a second completion.
        guard registeredCallbacks.insert(request.id).inserted else {
            DiggerManager.shared.startTask(for: request.url)
            saveManifests()
            return
        }

        seed
            .speed { speedBytes in
                Task { @MainActor in
                    guard self.manifests.contains(where: { $0.id == request.id }) else { return }
                    guard request.state.status == .downloading || request.state.status == .pending else { return }
                    let wasDownloading = request.state.status == .downloading
                    var newState = request.state
                    newState.status = .downloading
                    newState.speed = Self.speedFormatter.string(fromByteCount: Int64(speedBytes))
                    request.state = newState
                    if !wasDownloading {
                        self.refreshRunningTaskCount()
                    }
                }
            }
            .progress { progress in
                Task { @MainActor in
                    guard self.manifests.contains(where: { $0.id == request.id }) else { return }
                    guard request.state.status == .downloading || request.state.status == .pending else { return }
                    let now = CFAbsoluteTimeGetCurrent()
                    // Digger can report a transient out-of-range fraction
                    // during cancellation/size reconciliation. PackageState
                    // asserts that percent stays within zero and one.
                    let fraction = min(max(progress.fractionCompleted, 0), 1)
                    let last = self.lastProgressUpdates[request.id] ?? 0
                    guard fraction >= 1.0 || (now - last) >= 0.2 else { return }
                    self.lastProgressUpdates[request.id] = now

                    let wasDownloading = request.state.status == .downloading
                    var newState = request.state
                    newState.status = .downloading
                    newState.percent = fraction
                    request.state = newState
                    if !wasDownloading {
                        self.refreshRunningTaskCount()
                    }
                }
            }
            .completion { completion in
                Task { @MainActor in
                    self.registeredCallbacks.remove(request.id)
                    guard self.manifests.contains(where: { $0.id == request.id }) else {
                        self.releaseTransferSlot(request.id)
                        return
                    }
                    switch completion {
                    case let .success(url):
                        self.finalizingIDs.insert(request.id)
                        Task.detached {
                            do {
                                try await self.finalize(manifest: request, preparedContentAt: url)
                                await MainActor.run {
                                    self.finalizingIDs.remove(request.id)
                                    if self.manifests.contains(where: { $0.id == request.id }) {
                                        request.state.complete()
                                    } else {
                                        request.delete()
                                    }
                                    self.releaseTransferSlot(request.id)
                                    self.refreshRunningTaskCount()
                                    self.saveManifests()
                                    #if os(iOS)
                                        // Optional foreground preparation; signing and installation
                                        // of the resulting helper remain separate user actions.
                                        if self.manifests.contains(where: { $0.id == request.id }),
                                           UserDefaults.standard.bool(forKey: "Asspp.AutoPrepareDecrypt") {
                                            DecryptionCenter.shared.prepare(request)
                                        }
                                    #endif
                                }
                            } catch {
                                await MainActor.run {
                                    self.finalizingIDs.remove(request.id)
                                    if self.manifests.contains(where: { $0.id == request.id }) {
                                        request.state.error = error.localizedDescription
                                    } else {
                                        request.delete()
                                    }
                                    self.releaseTransferSlot(request.id)
                                    self.refreshRunningTaskCount()
                                    self.saveManifests()
                                }
                            }
                        }
                    case let .failure(error):
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                            // User-initiated cancellation via cancelTask(), not an error
                        } else if error is CancellationError {
                            // Swift structured concurrency cancellation
                        } else {
                            request.state.error = error.localizedDescription
                            self.saveManifests()
                        }
                        self.releaseTransferSlot(request.id)
                        self.refreshRunningTaskCount()
                    }
                }
            }
        DiggerManager.shared.startTask(for: request.url)
        saveManifests()
    }

    private func finalize(manifest: PackageManifest, preparedContentAt downloadedFile: URL) async throws {
        // Verify the main bundle identity and platform before signature injection.
        try StorePackageValidator.validate(at: downloadedFile, package: manifest.package)
        try? FileManager.default.createDirectory(
            at: manifest.targetLocation.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? FileManager.default.removeItem(at: manifest.targetLocation)

        let tempFile = manifest.targetLocation
            .deletingLastPathComponent()
            .appendingPathComponent(".\(manifest.targetLocation.lastPathComponent).unsigned")
        try? FileManager.default.removeItem(at: tempFile)

        logger.info("preparing signature: \(manifest.id)")
        try FileManager.default.moveItem(at: downloadedFile, to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        logger.info("injecting signatures: \(manifest.id)")
        try await SignatureInjector.inject(
            sinfs: manifest.signatures,
            iTunesMetadata: manifest.iTunesMetadata,
            into: tempFile.path,
        )

        logger.info("moving finalized file: \(manifest.id)")
        try FileManager.default.moveItem(at: tempFile, to: manifest.targetLocation)
    }

    func delete(request: PackageManifest) {
        logger.info("deleting download request id: \(request.id)")
        // Remove the observable row before doing any filesystem cleanup.
        // A successful transfer may still be injecting signatures; let its
        // completion clean up rather than removing the file underneath it.
        manifests.removeAll(where: { $0.id == request.id })
        queuedTransferIDs.removeAll { $0 == request.id }
        // Digger is not guaranteed to retain a task for an already-completed
        // download. Never cancel a stale URL when deleting a finished IPA.
        if activeTransferIDs.contains(request.id), !finalizingIDs.contains(request.id) {
            DiggerManager.shared.cancelTask(for: request.url)
        }
        registeredCallbacks.remove(request.id)
        releaseTransferSlot(request.id)
        if !finalizingIDs.contains(request.id) { request.delete() }
        lastProgressUpdates.removeValue(forKey: request.id)
        refreshRunningTaskCount()
        saveManifests()
    }

    func restart(request: PackageManifest) {
        logger.info("restarting download request id: \(request.id)")
        DiggerManager.shared.cancelTask(for: request.url)
        registeredCallbacks.remove(request.id)
        releaseTransferSlot(request.id)
        request.delete()
        request.state = .init()
        resume(request: request)
    }

    func removeAll() {
        for manifest in manifests { delete(request: manifest) }
    }

    private func releaseTransferSlot(_ id: UUID) {
        guard activeTransferIDs.remove(id) != nil else { return }
        while activeTransferIDs.count < 2 && !queuedTransferIDs.isEmpty {
            let nextID = queuedTransferIDs.removeFirst()
            guard let next = manifests.first(where: { $0.id == nextID }),
                  next.state.status == .pending else { continue }
            resume(request: next)
        }
    }
}

