import AsyncHTTPClient
import Foundation

public extension SAPSigner {
    /// Native Apple networking for setup, with one bounded NIO fallback for
    /// connection failures. Certificate verification remains enabled on both.
    static func connect() async throws -> SAPSigner {
        func exchange(url: String, payload: Data? = nil, key: String, stage: String) async throws -> Data {
            guard let endpoint = URL(string: url) else { throw SAPSetupTransport.Failure.unapprovedEndpoint }
            let request = try SAPSetupTransport.request(url: endpoint, payload: payload, userAgent: Configuration.userAgent)
            APLogger.info("AuthFix R2 \(stage): starting URLSession")
            let reply: SAPSetupTransport.Reply
            do {
                if #available(macOS 12.0, *) {
                    reply = try await SAPSetupTransport.exchange(request)
                } else {
                    throw URLError(.unsupportedURL)
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                let primary = SAPSetupTransport.diagnostic(error)
                APLogger.error("AuthFix R2 \(stage): URLSession failed (\(primary))")
                let legacyMac: Bool
                if #available(macOS 12.0, *) { legacyMac = false } else { legacyMac = true }
                guard SAPSetupTransport.shouldFallback(after: error) || legacyMac else {
                    throw AuthenticationConnectionError(stage: stage, primary: primary, fallback: nil)
                }
                APLogger.info("AuthFix R2 \(stage): trying NIO fallback")
                let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
                defer { _ = client.shutdown() }
                do {
                    let nioRequest = try HTTPClient.Request(
                        url: url, method: payload == nil ? .GET : .POST,
                        headers: .init(request.allHTTPHeaderFields?.map { ($0.key, $0.value) } ?? []),
                        body: request.httpBody.map { .data($0) }
                    )
                    let accumulator = ResponseAccumulator(request: nioRequest, maxBodySize: SAPSetupTransport.maximumBodySize)
                    let response = try await client.execute(request: nioRequest, delegate: accumulator).futureResult.get()
                    reply = .init(status: response.status.code, body: response.body.map { Data($0.readableBytesView) } ?? Data())
                } catch {
                    let fallback = SAPSetupTransport.diagnostic(error)
                    APLogger.error("AuthFix R2 \(stage): NIO failed (\(fallback))")
                    throw AuthenticationConnectionError(stage: stage, primary: primary, fallback: fallback)
                }
            }
            APLogger.info("AuthFix R2 \(stage): HTTP \(reply.status), bytes=\(reply.body.count)")
            do {
                return try SAPSetupTransport.payload(from: reply, key: key)
            } catch {
                throw SAPError.invalidInput("\(stage) returned an invalid setup response (HTTP \(reply.status))")
            }
        }

        let certificate = try await exchange(
            url: "https://s.mzstatic.com/sap/setupCert.plist", key: "sign-sap-setup-cert", stage: "SAP certificate"
        )
        let handshake = try SAPHandshake(certificate: certificate)
        let reply = try await exchange(
            url: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy", payload: handshake.request,
            key: "sign-sap-setup-buffer", stage: "SAP handshake"
        )
        let signer = try SAPSigner(session: handshake.complete(reply))
        APLogger.info("AuthFix R2: SAP session ready")
        return signer
    }
}
