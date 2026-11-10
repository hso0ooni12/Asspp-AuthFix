import Foundation

@main
struct DownloadRouteAdvisorChecks {
    static func main() async {
        let advisor = DownloadRouteAdvisor()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = "account-one|SA|iPhone"
        let second = "account-two|SA|iPhone"

        var allowed = await advisor.shouldTryPreferred(scope: first, now: start)
        precondition(allowed)
        await advisor.fallbackSucceededAfterPreferredFailure(scope: first, now: start)
        allowed = await advisor.shouldTryPreferred(scope: first, now: start)
        precondition(allowed)
        await advisor.fallbackSucceededAfterPreferredFailure(scope: first, now: start)
        allowed = await advisor.shouldTryPreferred(scope: first, now: start.addingTimeInterval(599))
        precondition(!allowed)
        allowed = await advisor.shouldTryPreferred(scope: second, now: start)
        precondition(allowed)
        allowed = await advisor.shouldTryPreferred(scope: first, now: start.addingTimeInterval(601))
        precondition(allowed)

        await advisor.fallbackSucceededAfterPreferredFailure(scope: first, now: start)
        await advisor.preferredSucceeded(scope: first)
        allowed = await advisor.shouldTryPreferred(scope: first, now: start)
        precondition(allowed)
        print("Preferred route cooldown, expiry, recovery and account isolation: PASS")
    }
}
