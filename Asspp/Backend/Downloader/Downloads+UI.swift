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

extension Downloads {
    func startDownload(for package: AppStore.AppPackage, accountID: String) async throws {
        let key = DownloadRequestIdentity(accountID: accountID,
                                          bundleID: package.software.bundleID,
                                          appID: package.software.id,
                                          platform: (package.entityType ?? .iPhone).rawValue,
                                          version: package.externalVersionID)
        if let existing = pendingDownloadRequests[key] {
            try await existing.value
            return
        }
        let task = Task { @MainActor in
            try await AppStore.this.withAccount(id: accountID) { account in
                let downloadOutput: DownloadOutput
                do {
                    downloadOutput = try await StoreDownloadService.download(account: &account.account, package: package)
                } catch ApplePackageError.licenseRequired {
                    // The Get action authorizes acquiring a FREE license, never
                    // charging the account or accepting Apple terms silently.
                    guard FreeLicensePolicy.shouldAcquire(price: package.software.price) else {
                        throw ApplePackageError.licenseRequired
                    }
                    logger.info("Free app lacks a license; acquiring and resuming requested download.")
                    do {
                        try await ApplePackage.Purchase.purchase(account: &account.account, app: package.software)
                    } catch {
                        if FreeLicensePolicy.isExpiredToken(error.localizedDescription) {
                            // Only pay the cost of an SAP refresh when Apple's
                            // response proves that the stored token has expired.
                            try await ApplePackage.Authenticator.rotatePasswordToken(for: &account.account)
                            try await ApplePackage.Purchase.purchase(account: &account.account, app: package.software)
                        } else if !FreeLicensePolicy.isAlreadyOwned(error.localizedDescription) {
                            throw error
                        }
                    }
                    // Exactly one retry after a successful purchase or an
                    // already-owned response; no unbounded request loops.
                    downloadOutput = try await StoreDownloadService.download(account: &account.account, package: package)
                }
                let request = try Downloads.this.add(request: .init(
                    account: account,
                    package: package,
                    downloadOutput: downloadOutput,
                ))
                Downloads.this.resume(request: request)
            }
        }
        pendingDownloadRequests[key] = task
        defer { pendingDownloadRequests[key] = nil }
        try await task.value
    }
}
