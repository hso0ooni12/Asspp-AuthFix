//
//  Downloads+UI.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import Foundation
import SwiftUI

enum DownloadAction: Hashable {
    case suspend
    case resume
    case restart
    case delete
}

@MainActor
extension Downloads {
    func performDownloadAction(for request: PackageManifest, action: DownloadAction) {
        switch action {
        case .suspend:
            suspend(request: request)
        case .resume:
            resume(request: request)
        case .restart:
            restart(request: request)
        case .delete:
            delete(request: request)
        }
    }

    func getAvailableActions(for request: PackageManifest) -> [DownloadAction] {
        switch request.state.status {
        case .pending, .downloading:
            [.suspend, .delete]
        case .paused:
            [.resume, .delete]
        case .failed:
            [.restart, .delete]
        case .completed:
            [.delete]
        }
    }

    func getActionLabel(for action: DownloadAction) -> (title: String, systemImage: String, isDestructive: Bool) {
        switch action {
        case .suspend:
            (String(localized: "Pause"), "stop.fill", false)
        case .resume:
            (String(localized: "Resume"), "play.fill", false)
        case .restart:
            (String(localized: "Restart Download"), "arrow.clockwise", false)
        case .delete:
            (String(localized: "Delete"), "trash", true)
        }
    }
}

struct DownloadRequestIdentity: Hashable {
    let accountID: String
    let bundleID: String
    let appID: Int64
    let platform: String
    let version: String?
}

enum DownloadRequestStage: String {
    case waitingForAccount = "Waiting for Apple Account"
    case connecting = "Connecting to App Store"
    case acquiringFreeLicense = "Requesting free license"
    case verifyingFreeLicense = "Verifying free license"
    case retrying = "Retrying connection"
    case preparingTransfer = "Preparing IPA download"
}

struct DownloadPreparationStatus {
    let appName: String
    let stage: DownloadRequestStage
    var retryAttempt: Int = 0

    var statusText: String {
        retryAttempt > 0
            ? "\(stage.rawValue) (\(retryAttempt)/\(StoreDownloadProtocol.maximumPreparationRetries))"
            : stage.rawValue
    }

    var compactLabel: String {
        switch stage {
        case .waitingForAccount: "Queued"
        case .connecting: "Connecting"
        case .acquiringFreeLicense: "License"
        case .verifyingFreeLicense: "Verifying"
        case .retrying: "Retry \(retryAttempt)/\(StoreDownloadProtocol.maximumPreparationRetries)"
        case .preparingTransfer: "Starting"
        }
    }
}

/// Apple account cookies and purchase/download tokens are mutable. In particular,
/// AppStore.withAccount reads a value, awaits a network operation, then writes
/// it back. Overlapping requests for different apps on the same Apple ID can
/// overwrite one another. Serialize only account metadata/license work; the
/// large IPA transfers still run concurrently (two at a time).
actor AccountDownloadGate {
    static let shared = AccountDownloadGate()
    private var held: Set<String> = []
    private struct Waiter {
        let interactive: Bool
        let continuation: CheckedContinuation<Void, Never>
    }
    private var waiters: [String: [Waiter]] = [:]

    func acquire(_ accountID: String, interactive: Bool = true) async {
        if held.insert(accountID).inserted { return }
        await withCheckedContinuation { continuation in
            waiters[accountID, default: []].append(Waiter(interactive: interactive, continuation: continuation))
        }
    }

    func release(_ accountID: String) {
        if var queue = waiters[accountID], !queue.isEmpty {
            let index = queue.firstIndex(where: \.interactive) ?? queue.startIndex
            let next = queue.remove(at: index)
            if queue.isEmpty { waiters.removeValue(forKey: accountID) }
            else { waiters[accountID] = queue }
            next.continuation.resume()
        } else {
            held.remove(accountID)
        }
    }
}

extension Downloads {
    func startDownload(for package: AppStore.AppPackage, accountID: String) async throws {
        if let existing = downloadRequest(forArchive: package),
           [.pending, .downloading, .completed].contains(existing.state.status) {
            return
        }
        let key = DownloadRequestIdentity(accountID: accountID,
                                          bundleID: package.software.bundleID,
                                          appID: package.software.id,
                                          platform: (package.entityType ?? .iPhone).rawValue,
                                          version: package.externalVersionID)
        if let existing = pendingDownloadRequests[key] {
            try await existing.value
            return
        }
        if let existing = pendingDownloadRequests.first(where: {
            $0.key.bundleID == key.bundleID &&
                $0.key.platform == key.platform &&
                $0.key.version == key.version
        })?.value {
            try await existing.value
            return
        }
        pendingPreparations[key] = .init(appName: package.software.name, stage: .waitingForAccount)
        let startedAt = ContinuousClock.now
        let task = Task { @MainActor in
            await AccountDownloadGate.shared.acquire(accountID)
            pendingPreparations[key] = .init(appName: package.software.name, stage: .connecting)
            logger.info("Store preparation: account wait=\(startedAt.duration(to: .now))")
            defer { Task { await AccountDownloadGate.shared.release(accountID) } }
            try Task.checkCancellation()
            try await AppStore.this.withAccount(id: accountID) { account in
                let attempt = StoreDownloadService.DownloadAttempt()
                let downloadOutput: DownloadOutput
                do {
                    downloadOutput = try await self.prepareTicketWithRetries(
                        account: &account.account, package: package, key: key, attempt: attempt)
                } catch ApplePackageError.licenseRequired {
                    // The Get action authorizes acquiring a FREE license, never
                    // charging the account or accepting Apple terms silently.
                    guard FreeLicensePolicy.shouldAcquire(price: package.software.price) else {
                        throw ApplePackageError.licenseRequired
                    }
                    pendingPreparations[key] = .init(appName: package.software.name, stage: .acquiringFreeLicense)
                    logger.info("Free app lacks a license; acquiring and resuming requested download.")
                    let licenseStartedAt = ContinuousClock.now
                    do {
                        do {
                            try await ApplePackage.Purchase.purchase(account: &account.account, app: package.software)
                        } catch where FreeLicensePolicy.isExpiredToken(error.localizedDescription) {
                            try await ApplePackage.Authenticator.rotatePasswordToken(for: &account.account)
                            try await ApplePackage.Purchase.purchase(account: &account.account, app: package.software)
                        }
                    } catch {
                        logger.info("Free license request failed: \(StoreDiagnostics.errorSummary(error))")
                        guard FreeLicensePolicy.isTransportInterruption(error) ||
                            FreeLicensePolicy.isAlreadyOwned(error.localizedDescription)
                        else {
                            throw error
                        }
                    }
                    logger.info("Free license request finished in \(licenseStartedAt.duration(to: .now))")
                    downloadOutput = try await self.verifyFreeLicense(
                        account: &account.account, package: package, key: key, attempt: attempt)
                }
                pendingPreparations[key] = .init(appName: package.software.name, stage: .preparingTransfer)
                var resolvedPackage = package
                // Historical rows already use the version verified in the package.
                if package.externalVersionID == nil, !downloadOutput.bundleShortVersionString.isEmpty {
                    resolvedPackage.software.version = downloadOutput.bundleShortVersionString
                }
                let request = try Downloads.this.add(request: .init(
                    account: account,
                    package: resolvedPackage,
                    downloadOutput: downloadOutput,
                ))
                Downloads.this.resume(request: request)
            }
        }
        pendingDownloadRequests[key] = task
        defer {
            pendingDownloadRequests[key] = nil
            pendingPreparations[key] = nil
            logger.info("Store preparation finished in \(startedAt.duration(to: .now))")
        }
        try await task.value
    }

    /// Automatically repeat a safe download-ticket read after transient
    /// networking failures. Never replay Apple license acquisition.
    private func prepareTicketWithRetries(
        account: inout Account, package: AppStore.AppPackage, key: DownloadRequestIdentity,
        attempt: StoreDownloadService.DownloadAttempt
    ) async throws -> DownloadOutput {
        var retries = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await StoreDownloadService.download(account: &account, package: package, attempt: attempt)
            } catch {
                try Task.checkCancellation()
                guard StoreDownloadProtocol.shouldRetryPreparation(error, completedRetries: retries) else {
                    throw error
                }
                retries += 1
                pendingPreparations[key] = .init(appName: package.software.name,
                                                 stage: .retrying, retryAttempt: retries)
                logger.info("Transient Apple ticket failure; safe read retry \(retries)/\(StoreDownloadProtocol.maximumPreparationRetries)")
                try await Task.sleep(nanoseconds:
                    StoreDownloadProtocol.preparationRetryDelayNanoseconds(retries - 1))
                pendingPreparations[key] = .init(appName: package.software.name, stage: .connecting)
            }
        }
    }

    /// Apple can take a moment to expose a newly granted license to downloads.
    /// The same ticket checks cover a connection drop during acquisition.
    private func verifyFreeLicense(
        account: inout Account, package: AppStore.AppPackage, key: DownloadRequestIdentity,
        attempt: StoreDownloadService.DownloadAttempt
    ) async throws -> DownloadOutput {
        let startedAt = ContinuousClock.now
        defer { logger.info("Free license verification finished in \(startedAt.duration(to: .now))") }
        let delays = FreeLicensePolicy.verificationDelays
        for retry in 0 ... delays.count {
            try Task.checkCancellation()
            pendingPreparations[key] = .init(appName: package.software.name,
                stage: .verifyingFreeLicense, retryAttempt: retry)
            do {
                return try await StoreDownloadService.download(account: &account, package: package, attempt: attempt)
            } catch ApplePackageError.licenseRequired {
                guard retry < delays.count else {
                    throw NSError(domain: "Velo.LicenseTransport", code: 1, userInfo: [
                        NSLocalizedDescriptionKey:
                            "Apple has not confirmed the free license. Verify this app under your Apple Account in the App Store before trying again."
                    ])
                }
                try await Task.sleep(for: delays[retry])
            }
        }
        throw StoreDownloadError.empty
    }
}
