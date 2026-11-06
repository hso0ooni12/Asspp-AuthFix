import Foundation

public struct AuthenticationDeliveryError: LocalizedError, Sendable {
    let statuses: [UInt]

    public var errorDescription: String? {
        let summary = statuses.map { String($0) }.joined(separator: ", ")
        return "AuthFix R2: Apple returned no usable sign-in response (HTTP \(summary)). Recovery attempts are exhausted. No account authentication result was received."
    }
}

/// Recovery applies only to replies without an App Store business response.
/// Credential errors, verification challenges and rate limits are never replayed.
enum AuthenticationRecovery {
    static let attemptsPerRoute = 2
    static let maximumSends = 12

    static func shouldRetry(status: UInt, body: Data, hasLocation: Bool) -> Bool {
        if !body.isEmpty,
           let value = try? PropertyListSerialization.propertyList(from: body, format: nil),
           value is [String: Any]
        {
            return false
        }
        if status == 403 || status == 429 { return false }
        if (300 ... 399).contains(status) { return !hasLocation }
        return status == 204 || status == 404 || (500 ... 599).contains(status)
            || (status == 200 && body.isEmpty)
    }

    /// Keep the bag route first. A slash variant and the native route are
    /// experimental fallbacks; all routes use verified Apple HTTPS and SAP.
    static func routes(from endpoint: URL, deviceIdentifier: String) -> [URL] {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.user == nil, endpoint.password == nil,
              endpoint.port == nil || endpoint.port == 443,
              let host = endpoint.host?.lowercased()
        else { return [] }

        let legacyHost = host == "buy.itunes.apple.com"
            || host.range(of: "^p[0-9]+-buy[.]itunes[.]apple[.]com$", options: .regularExpression) != nil
        let legacyPath = "/WebObjects/MZFinance.woa/wa/authenticate"
        let nativePath = "/auth/v1/native/fast/"
        var result: [URL] = []

        if legacyHost && [legacyPath, legacyPath + "/"].contains(endpoint.path) {
            result.append(endpoint)
            if var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
                // Foundation's URL.path may hide a trailing slash. Inspect the
                // URLComponents path so this really produces the other variant.
                components.path = components.path.hasSuffix("/") ? legacyPath : legacyPath + "/"
                if let alternate = components.url, alternate != endpoint { result.append(alternate) }
            }
            var native = URLComponents()
            native.scheme = "https"
            native.host = "auth.itunes.apple.com"
            native.path = nativePath
            native.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
            if let url = native.url { result.append(url) }
        } else if host == "auth.itunes.apple.com",
                  [nativePath, String(nativePath.dropLast())].contains(endpoint.path)
        {
            result.append(endpoint)
        }
        return result
    }
}
