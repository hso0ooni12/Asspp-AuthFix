@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import XCTest

@MainActor
final class SAPSetupTransportTests: XCTestCase {
    func testApprovedRequestsAndSetupPayload() throws {
        let certificate = try SAPSetupTransport.request(
            url: XCTUnwrap(URL(string: "https://s.mzstatic.com/sap/setupCert.plist")), payload: nil, userAgent: "test-agent"
        )
        XCTAssertEqual(certificate.httpMethod, "GET")
        XCTAssertNil(certificate.httpBody)
        XCTAssertFalse(certificate.httpShouldHandleCookies)
        let payload = Data([1, 2, 3, 4])
        let setup = try SAPSetupTransport.request(
            url: XCTUnwrap(URL(string: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy")), payload: payload, userAgent: "test-agent"
        )
        let body = try XCTUnwrap(setup.httpBody)
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Data])
        XCTAssertEqual(setup.httpMethod, "POST")
        XCTAssertEqual(fields, ["sign-sap-setup-buffer": payload])
        XCTAssertEqual(setup.value(forHTTPHeaderField: "User-Agent"), "test-agent")
    }

    func testRejectsOtherHostsPathsMethodsAndURLCredentials() throws {
        for url in [
            "http://s.mzstatic.com/sap/setupCert.plist",
            "https://s.mzstatic.com.evil.invalid/sap/setupCert.plist",
            "https://s.mzstatic.com/another-path",
            "https://user:password@s.mzstatic.com/sap/setupCert.plist",
            "https://s.mzstatic.com/sap/setupCert.plist?token=secret",
            "https://s.mzstatic.com:8443/sap/setupCert.plist",
        ] {
            XCTAssertThrowsError(try SAPSetupTransport.request(url: XCTUnwrap(URL(string: url)), payload: nil, userAgent: "test"))
        }
        XCTAssertThrowsError(try SAPSetupTransport.request(
            url: XCTUnwrap(URL(string: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy")), payload: nil, userAgent: "test"
        ))
    }

    func testReplyLimitsAndProtocolValidation() throws {
        let content = try PropertyListSerialization.data(fromPropertyList: ["key": Data([1, 2])], format: .xml, options: 0)
        XCTAssertEqual(try SAPSetupTransport.payload(from: .init(status: 200, body: content), key: "key"), Data([1, 2]))
        XCTAssertThrowsError(try SAPSetupTransport.payload(from: .init(status: 204, body: Data()), key: "key"))
        XCTAssertThrowsError(try SAPSetupTransport.payload(from: .init(status: 200, body: Data("<html/>".utf8)), key: "key"))
        XCTAssertThrowsError(try SAPSetupTransport.payload(from: .init(status: 200, body: content), key: "missing"))
        XCTAssertThrowsError(try SAPSetupTransport.payload(
            from: .init(status: 200, body: Data(repeating: 0, count: SAPSetupTransport.maximumBodySize + 1)), key: "key"
        ))
    }

    func testFallbackExcludesCancellationAndTrustFailures() {
        XCTAssertTrue(SAPSetupTransport.shouldFallback(after: URLError(.timedOut)))
        XCTAssertTrue(SAPSetupTransport.shouldFallback(after: URLError(.cannotConnectToHost)))
        XCTAssertFalse(SAPSetupTransport.shouldFallback(after: URLError(.cancelled)))
        XCTAssertFalse(SAPSetupTransport.shouldFallback(after: URLError(.serverCertificateUntrusted)))
        XCTAssertFalse(SAPSetupTransport.shouldFallback(after: URLError(.secureConnectionFailed)))
    }

    func testNumericDiagnosticsPreserveRealPOSIXCodeWithoutSecrets() {
        #if canImport(Network)
            let networkError = HTTPClient.NWPOSIXError(.ETIMEDOUT, reason: "do-not-log@example.invalid secret")
            XCTAssertEqual(SAPSetupTransport.diagnostic(networkError), "Network POSIX errno=\(POSIXErrorCode.ETIMEDOUT.rawValue)")
        #endif
        let genericError = NSError(domain: "secret@example.invalid", code: 123, userInfo: [NSLocalizedDescriptionKey: "private password"])
        XCTAssertEqual(SAPSetupTransport.diagnostic(genericError), "transport error code=123")
    }

    func testNativeSessionHasNoSharedCookiesOrCredentialStorage() {
        let configuration = SAPSetupTransport.configuration()
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.tlsMinimumSupportedProtocolVersion, .TLSv12)
    }

    func testAutomaticRedirectsAreRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://s.mzstatic.com/sap/setupCert.plist"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.invalid"]))
        let rejected = expectation(description: "redirect rejected")
        SAPSetupTransport.NoRedirects().urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://example.invalid")!)
        ) { request in
            XCTAssertNil(request)
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 1)
    }

    func testLiveSetupWithoutAppleAccount() async throws {
        guard ProcessInfo.processInfo.environment["ASSPP_AUTHFIX_SETUP_PROBE"] == "1" else {
            throw XCTSkip("Explicit opt-in for Apple's public SAP setup service")
        }
        let previousIdentifier = Configuration.deviceIdentifier
        Configuration.deviceIdentifier = "001122334455"
        defer { Configuration.deviceIdentifier = previousIdentifier }
        let signer = try await SAPSigner.connect()
        let calls = await signer.calls
        XCTAssertEqual(calls, 0)
        print("AuthFix R2: live SAP setup completed without an Apple account or sign-in request.")
    }
}
