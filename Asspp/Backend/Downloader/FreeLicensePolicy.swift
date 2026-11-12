import Foundation

/// Pure decision policy: one Get tap can acquire a missing FREE license.
/// Nothing ever authorizes automatic paid purchases.
enum FreeLicensePolicy {
    static func shouldAcquire(price: Double?) -> Bool {
        guard let price, price.isFinite else { return false }
        return price == 0
    }

    static func isExpiredToken(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("password token is expired")
            || text.contains("password token expired")
            || text.contains("failuretype: 2034")
            || text.contains("failuretype: 2042")
    }

    /// ApplePackage's SwiftNIO transport can fail before Apple's free-license
    /// endpoint returns a response. A failed POST must not be blindly repeated.
    static func isTransportInterruption(_ error: Error) -> Bool {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain {
            return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                    NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet].contains(failure.code)
        }
        return failure.code == 1 &&
            (failure.domain.contains("NWPOSIXError") || failure.domain == NSPOSIXErrorDomain)
    }

    static func isAlreadyOwned(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("failuretype: 5002")
            || text.contains("app is already purchased")
    }
}
