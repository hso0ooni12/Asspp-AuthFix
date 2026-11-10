import Foundation

/// Remembers when the experimental R3 transport repeatedly fails but the
/// verified legacy transport succeeds. The decision is in-memory, account-
/// scoped, and expires automatically; no credentials or URLs are persisted.
actor DownloadRouteAdvisor {
    static let shared = DownloadRouteAdvisor()

    private struct Observation {
        var consecutiveFallbacks = 0
        var preferredPausedUntil: Date?
    }

    private var observations: [String: Observation] = [:]
    private let failureThreshold = 2
    private let cooldown: TimeInterval = 10 * 60

    func shouldTryPreferred(scope: String, now: Date = Date()) -> Bool {
        guard var observation = observations[scope],
              let until = observation.preferredPausedUntil else { return true }
        if now < until { return false }
        // Re-probe once after the cooldown instead of permanently disabling R3.
        observation.preferredPausedUntil = nil
        observation.consecutiveFallbacks = 0
        observations[scope] = observation
        return true
    }

    func preferredSucceeded(scope: String) {
        observations.removeValue(forKey: scope)
    }

    func fallbackSucceededAfterPreferredFailure(scope: String, now: Date = Date()) {
        var observation = observations[scope] ?? Observation()
        observation.consecutiveFallbacks += 1
        if observation.consecutiveFallbacks >= failureThreshold {
            observation.consecutiveFallbacks = 0
            observation.preferredPausedUntil = now.addingTimeInterval(cooldown)
        }
        observations[scope] = observation
    }
}
