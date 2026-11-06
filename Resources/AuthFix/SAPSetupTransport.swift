import AsyncHTTPClient
import Foundation

/// A stage name and numeric transport codes, without request URLs or secrets.
public struct AuthenticationConnectionError: LocalizedError, Sendable {
    let stage: String
    let primary: String
    let fallback: String?

    public var errorDescription: String? {
        let detail = fallback.map { "URLSession: \(primary); NIO: \($0)" } ?? primary
        return "AuthFix R2: connection failed during \(stage) (\(detail))."
    }
}

enum SAPSetupTransport {
    struct Reply: Sendable {
        let status: UInt
        let body: Data
    }

    enum Failure: Error {
        case unapprovedEndpoint
        case oversizedResponse
        case nonHTTPResponse
        case invalidSetupResponse(UInt)
    }

    static let maximumBodySize = 2 * 1024 * 1024

    static func request(url: URL, payload: Data?, userAgent: String) throws -> URLRequest {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, url.fragment == nil
        else { throw Failure.unapprovedEndpoint }
        let certificate = url.host?.lowercased() == "s.mzstatic.com" && url.path == "/sap/setupCert.plist" && payload == nil
        let setup = url.host?.lowercased() == "fpinit.itunes.apple.com" && url.path == "/v1/signSapSetup/legacy" && payload != nil
        guard certificate || setup else { throw Failure.unapprovedEndpoint }
        guard (payload?.count ?? 0) <= 1 << 20 else { throw Failure.oversizedResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.httpBody = try payload.map {
            try PropertyListSerialization.data(fromPropertyList: ["sign-sap-setup-buffer": $0], format: .xml, options: 0)
        }
        return request
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return configuration
    }

    @available(macOS 12.0, *)
    static func exchange(_ request: URLRequest) async throws -> Reply {
        let session = URLSession(configuration: configuration(), delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.nonHTTPResponse }
        guard response.expectedContentLength <= maximumBodySize else { throw Failure.oversizedResponse }
        var body = Data()
        body.reserveCapacity(min(maximumBodySize, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard body.count < maximumBodySize else { throw Failure.oversizedResponse }
            body.append(byte)
        }
        return Reply(status: UInt(response.statusCode), body: body)
    }

    static func payload(from reply: Reply, key: String) throws -> Data {
        guard reply.body.count <= maximumBodySize else { throw Failure.oversizedResponse }
        guard reply.status == 200,
              let plist = try? PropertyListSerialization.propertyList(from: reply.body, format: nil) as? [String: Any],
              let data = plist[key] as? Data, !data.isEmpty, data.count <= 1 << 20
        else { throw Failure.invalidSetupResponse(reply.status) }
        return data
    }

    static func shouldFallback(after error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
    }

    static func diagnostic(_ error: Error) -> String {
        #if canImport(Network)
            if let error = error as? HTTPClient.NWPOSIXError { return "Network POSIX errno=\(error.errorCode.rawValue)" }
            if let error = error as? HTTPClient.NWTLSError { return "Network TLS status=\(error.status)" }
        #endif
        if let error = error as? URLError { return "URL error=\(error.code.rawValue)" }
        if let error = error as? POSIXError { return "POSIX errno=\(error.code.rawValue)" }
        if error is CancellationError { return "cancelled" }
        let code = (error as NSError).code
        return "transport error code=\(code)"
    }

    /// Keep setup payloads on their original, explicitly approved Apple endpoint.
    final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
