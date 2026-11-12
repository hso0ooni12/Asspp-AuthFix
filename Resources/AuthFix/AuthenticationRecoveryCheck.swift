import Foundation

@main
struct AuthenticationRecoveryCheck {
    enum Failure: Error { case check(String) }

    static func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw Failure.check(name) }
    }

    static func main() throws {
        try require(AuthenticationRecovery.maximumSends == 6, "bounded sign-in delivery")
        try require(AuthenticationRecovery.isMissingEndpoint(404), "missing route 404")
        try require(AuthenticationRecovery.isMissingEndpoint(204), "missing route 204")
        try require(!AuthenticationRecovery.isMissingEndpoint(403), "403 is not missing endpoint")
        let sample = AuthenticationDeliveryError(statuses: [404, 204, 404])
        try require(sample.errorDescription?.contains("sign-in endpoints are unavailable") == true,
                    "actionable Apple sign-in service failure")
        let empty = Data()
        let html = Data("<html><title>404 Not Found</title></html>".utf8)
        let businessReply = try PropertyListSerialization.data(
            fromPropertyList: ["failureType": "5005"], format: .xml, options: 0
        )
        for code: UInt in [204, 404, 502, 503] {
            try require(AuthenticationRecovery.shouldRetry(status: code, body: empty, hasLocation: false), "empty \(code)")
        }
        try require(AuthenticationRecovery.shouldRetry(status: 404, body: html, hasLocation: false), "HTML 404")
        for code: UInt in [200, 403, 404, 429, 503] {
            try require(!AuthenticationRecovery.shouldRetry(status: code, body: businessReply, hasLocation: false), "business reply \(code)")
        }
        for code: UInt in [401, 403, 429] {
            try require(!AuthenticationRecovery.shouldRetry(status: code, body: empty, hasLocation: false), "no replay \(code)")
        }
        try require(!AuthenticationRecovery.shouldRetry(status: 302, body: empty, hasLocation: true), "real redirect")
        try require(AuthenticationRecovery.shouldRetry(status: 301, body: html, hasLocation: false), "bare redirect")

        for suffix in ["", "/"] {
            let input = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate\(suffix)?guid=012345ABCDEF&Pod=25")!
            let routes = AuthenticationRecovery.routes(from: input, deviceIdentifier: "012345ABCDEF")
            try require(routes.count == 3 && Set(routes).count == 3, "three distinct routes")
            try require(routes.first == input, "bag route remains first")
            let native = URLComponents(url: routes[2], resolvingAgainstBaseURL: false)!
            try require(native.host == "auth.itunes.apple.com" && native.path == "/auth/v1/native/fast/", "native fallback")
            try require(native.queryItems == [URLQueryItem(name: "guid", value: "012345ABCDEF")], "no legacy routing or credential query in fallback")
        }
        for input in [
            "http://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "https://buy.itunes.apple.com.evil.invalid/WebObjects/MZFinance.woa/wa/authenticate",
            "https://user:password@buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "https://pfoo-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "https://buy.itunes.apple.com:8443/WebObjects/MZFinance.woa/wa/authenticate",
        ] {
            try require(AuthenticationRecovery.routes(from: URL(string: input)!, deviceIdentifier: "012345ABCDEF").isEmpty, "reject unapproved route")
        }
        print("Authentication recovery checks passed: transient replies, business errors, redirects and destination boundaries.")
    }
}
