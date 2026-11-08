import Foundation

private final class NativeCalls: @unchecked Sendable {
    static let shared = NativeCalls()
    private let lock = NSLock()
    private var calls: [String: Int] = [:]

    func record(_ key: String) {
        lock.lock()
        calls[key, default: 0] += 1
        lock.unlock()
    }

    func count(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls[key, default: 0]
    }
}

// Test boundary substitutes the expensive native engine, never Apple accounts.
enum R3KBSync {
    struct Generation: Sendable {
        let blob: String?
        let status: String
    }

    static func generate(guid: String, directoryServicesIdentifier: String) -> Generation {
        NativeCalls.shared.record(guid + ":" + directoryServicesIdentifier)
        Thread.sleep(forTimeInterval: 0.1)
        return directoryServicesIdentifier == "999"
            ? Generation(blob: nil, status: "guest")
            : Generation(blob: "test", status: "ready")
    }
}

@main
struct PreparationChecks {
    static func main() async {
        let preparation = DownloadPreparation()
        await withTaskGroup(of: R3KBSync.Generation.self) { group in
            for index in 0..<24 {
                group.addTask {
                    await preparation.generation(guid: index.isMultiple(of: 2) ? "aabbccddeeff" : "AABBCCDDEEFF",
                                                 dsid: index.isMultiple(of: 2) ? "100" : " 100 ")
                }
            }
            for await result in group { precondition(result.status == "ready") }
        }
        precondition(NativeCalls.shared.count("AABBCCDDEEFF:100") == 1,
                     "Concurrent warm-up and download duplicated expensive native work")

        _ = await preparation.generation(guid: "AABBCCDDEEFF", dsid: "200")
        precondition(NativeCalls.shared.count("AABBCCDDEEFF:200") == 1,
                     "Another account incorrectly reused in-flight data")

        for _ in 0..<2 {
            let result = await preparation.generation(guid: "AABBCCDDEEFF", dsid: "999")
            precondition(result.blob == nil)
        }
        precondition(NativeCalls.shared.count("AABBCCDDEEFF:999") == 2,
                     "A failed preparation was cached instead of allowing a retry")
        print("Download preparation coalescing, account isolation and failure retry: PASS")
    }
}
