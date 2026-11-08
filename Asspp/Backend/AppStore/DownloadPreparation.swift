import Foundation

/// Coalesces foreground warm-up and a real download into a single native call.
/// The native bridge retains successful account/hardware-bound blobs in memory;
/// this actor stores only in-flight work. No credentials or blobs are persisted.
actor DownloadPreparation {
    static let shared = DownloadPreparation()

    private struct Key: Hashable, Sendable {
        let guid: String
        let dsid: String
    }

    private struct Work {
        let id: UUID
        let task: Task<R3KBSync.Generation, Never>
    }

    private var pending: [Key: Work] = [:]

    func generation(guid: String, dsid: String,
                    priority: TaskPriority = .userInitiated) async -> R3KBSync.Generation {
        let key = Key(guid: guid.uppercased(), dsid: dsid.trimmingCharacters(in: .whitespacesAndNewlines))
        if let existing = pending[key] { return await existing.task.value }
        let work = Work(id: UUID(), task: Task.detached(priority: priority) {
            R3KBSync.generate(guid: key.guid, directoryServicesIdentifier: key.dsid)
        })
        pending[key] = work
        let result = await work.task.value
        if pending[key]?.id == work.id { pending[key] = nil }
        return result
    }
}
