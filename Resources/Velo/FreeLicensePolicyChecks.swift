import Foundation

@main struct Check {
    static func main() {
        precondition(FreeLicensePolicy.shouldAcquire(price: 0))
        precondition(!FreeLicensePolicy.shouldAcquire(price: nil))
        precondition(!FreeLicensePolicy.shouldAcquire(price: 2.99))
        precondition(!FreeLicensePolicy.shouldAcquire(price: .nan))
        precondition(FreeLicensePolicy.isExpiredToken("password token is expired (failureType: 2034)"))
        precondition(FreeLicensePolicy.isExpiredToken("failureType: 2042"))
        precondition(!FreeLicensePolicy.isExpiredToken("Network timeout"))
        precondition(FreeLicensePolicy.isAlreadyOwned("app is already purchased (failureType: 5002)"))
        precondition(!FreeLicensePolicy.isAlreadyOwned("failureType: 2059"))
        print("PASS FreeLicensePolicy: free-only, bounded token refresh and already-owned semantics")
    }
}
