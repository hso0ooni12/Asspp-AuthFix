#if os(iOS)
import SwiftUI

enum DirectDecryptionStatus: Equatable {
    case idle
    case running(String)
    case succeeded(String)
    case failed(String)
}

@MainActor
@Observable
final class DirectDecryptionCenter {
    static let shared = DirectDecryptionCenter()
    private(set) var activeID: UUID?
    private var statuses: [UUID: DirectDecryptionStatus] = [:]
    private var reports: [UUID: URL] = [:]
    private var outputs: [UUID: URL] = [:]

    var isBusy: Bool { activeID != nil }
    func status(_ manifest: PackageManifest) -> DirectDecryptionStatus { statuses[manifest.id] ?? .idle }
    func hasReport(_ manifest: PackageManifest) -> Bool { reports[manifest.id] != nil }
    func hasOutput(_ manifest: PackageManifest) -> Bool { outputs[manifest.id] != nil }

    func shareReport(_ manifest: PackageManifest) {
        if let url = reports[manifest.id] { DecryptionCenter.shared.sharePackage = PreparedDecryptionPackage(url: url) }
    }

    func shareOutput(_ manifest: PackageManifest) {
        if let url = outputs[manifest.id] { DecryptionCenter.shared.sharePackage = PreparedDecryptionPackage(url: url) }
    }

    func start(_ manifest: PackageManifest) {
        guard manifest.completed, !isBusy else { return }
        let id = manifest.id
        activeID = id
        statuses[id] = .running("Starting direct FairPlayed...")
        let request = DirectDecryptionRequest(
            input: manifest.targetLocation,
            bundleID: manifest.package.software.bundleID,
            name: manifest.package.software.name,
            version: manifest.package.software.version,
            outputDirectory: documentsDirectory.appendingPathComponent("FairPlayed/Direct", isDirectory: true)
        )
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DirectFairPlayed.run(request) { stage in
                    Task { @MainActor in
                        guard self.activeID == id else { return }
                        self.statuses[id] = .running(stage)
                    }
                }
            }.value
            if let report = outcome.report { reports[id] = report }
            if let output = outcome.output {
                outputs[id] = output
                statuses[id] = .succeeded(outcome.message)
                // Use the existing single share-sheet owner at the tab root.
                DecryptionCenter.shared.sharePackage = PreparedDecryptionPackage(url: output)
            } else {
                statuses[id] = .failed(outcome.message)
            }
            activeID = nil
        }
    }
}

struct DirectDecryptionControls: View {
    let manifest: PackageManifest
    @State private var center = DirectDecryptionCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                center.start(manifest)
            } label: {
                Label("Try Direct Decrypt", systemImage: "bolt.shield")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AssppTheme.accent)
            .disabled(center.isBusy)

            switch center.status(manifest) {
            case .idle:
                Text("Experimental · runs inside Asspp")
                    .font(.caption).foregroundStyle(.secondary)
            case let .running(stage):
                ProgressView(stage).font(.footnote)
            case let .succeeded(message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            case let .failed(message):
                Text(message).font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if center.hasOutput(manifest) {
                Button("Share Decrypted IPA", systemImage: "square.and.arrow.up") { center.shareOutput(manifest) }
                    .font(.footnote)
            }
            if center.hasReport(manifest) {
                Button("Share Diagnostic Report", systemImage: "doc.text") { center.shareReport(manifest) }
                    .font(.footnote)
            }
        }
    }
}
#endif
