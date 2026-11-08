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

    static func isAlreadyOwned(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("failuretype: 5002")
            || text.contains("app is already purchased")
    }
}
