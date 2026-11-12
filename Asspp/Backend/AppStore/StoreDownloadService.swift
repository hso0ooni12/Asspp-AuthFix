import ApplePackage
import Foundation
import ZIPFoundation

/// Reuse the known-working R20/R17 per-request Apple URLSession. Keep Apple's raw bodies, cookies and signed
/// asset URLs out of both the Xcode console and the in-app log viewer.
enum StoreDownloadService {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_: URLSession, task _: URLSessionTask,
                        willPerformHTTPRedirection _: HTTPURLResponse,
                        newRequest _: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void)
        {
            completionHandler(nil)
        }
    }

    static func download(account: inout Account, package: AppStore.AppPackage) async throws -> DownloadOutput {
        let email = account.email
        return try await product(account: &account, package: package, version: package.externalVersionID, operation: "download") { item in
            try await output(item: item, email: email, bundleID: package.software.bundleID)
        }
    }

    static func versions(account: inout Account, package: AppStore.AppPackage) async throws -> [String] {
        do {
            return try await product(account: &account, package: package,
                                     version: package.externalVersionID, operation: "versions") { item in
                try StoreDownloadProtocol.historyIdentifiers(from: item)
            }
        } catch {
            let initialFailure = error
            guard let failure = error as? StoreDownloadError else { throw error }
            switch failure {
            case .response(403), .emptyResponse(403):
                // Apple's legacy download endpoint can deny version-history
                // requests that still work through the account-bound modern
                // ent/download route. Try exactly once; never forge IDs or
                // retry the rejected endpoint indefinitely.
                do {
                    return try await product(account: &account, package: package,
                                             version: package.externalVersionID,
                                             operation: "versions-modern") { item in
                        try StoreDownloadProtocol.historyIdentifiers(from: item)
                    }
                } catch {
                    try Task.checkCancellation()
                    logger.info("Modern history route unavailable: \(StoreDiagnostics.errorSummary(error))")
                    throw initialFailure
                }
            case .noVersions, .empty: break
            default: throw error
            }
            // Apple's unpinned response sometimes omits the history array.
            // Query the current version for the exact store and platform, then
            // ask for its metadata explicitly. Never substitute another app.
            guard let region = Configuration.countryCode(for: account.store) else {
                throw StoreDownloadError.noVersions
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let current: StoreDownloadProtocol.CatalogVersion
            do {
                current = try await catalogVersion(session: session, appID: package.software.id,
                                                   region: region, platform: package.entityType ?? .iPhone,
                                                   trace: "history")
            } catch {
                throw StoreDownloadError.noVersions
            }
            guard current.bundleID == nil || current.bundleID == package.software.bundleID else {
                throw StoreDownloadError.noVersions
            }
            return try await product(account: &account, package: package,
                                     version: current.externalVersionID, operation: "versions-pinned") { item in
                try StoreDownloadProtocol.historyIdentifiers(from: item)
            }
        }
    }

    /// The ticket request runs under the account lock; the signed IPA
    /// Range reader runs outside that lock to avoid delaying GET.
    static func versionAsset(account: inout Account, package: AppStore.AppPackage, versionID: String) async throws -> URL {
        try await product(account: &account, package: package, version: versionID, operation: "version-metadata") { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            guard StoreProtocol.string(metadata["softwareVersionExternalIdentifier"]) == versionID,
                  let address = item["URL"] as? String,
                  let url = URL(string: address), url.scheme == "https", url.host != nil
            else { throw StoreDownloadError.invalidPackage }
            return url
        }
    }

    static func versionMetadataFromAsset(_ url: URL, bundleID: String) async throws -> VersionMetadata {
        let info = try await RemoteIPAInfoPlist.read(url: url, bundleID: bundleID)
        return VersionMetadata(displayVersion: info.version, releaseDate: info.date)
    }

    private static func product<Result>(account: inout Account, package: AppStore.AppPackage, version: String?, operation: String, parse: ([String: Any]) async throws -> Result) async throws -> Result {
        let trace = String(UUID().uuidString.prefix(8))
        let app = package.software
        let version = version.flatMap { $0.isEmpty ? nil : $0 }
        let platform = package.entityType ?? .iPhone
        logger.info("Store download [\(trace)]: operation=\(operation) app=\(app.id) platform=\(platform.rawValue) store=\(account.store) version=\(version ?? "latest")")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let region = Configuration.countryCode(for: account.store)
            var effectiveVersion = version
            // Only the in-memory route decision uses this identity. Never log
            // or persist a DSID, cookie, password token, or signed IPA URL.
            let routeScope = "\(account.directoryServicesIdentifier)|\(account.store)|\(platform.rawValue)"
            let tryPreferred: Bool
            let modernHistoryOnly = operation == "versions-modern"
            if modernHistoryOnly {
                tryPreferred = true
            } else if operation == "download" {
                tryPreferred = await DownloadRouteAdvisor.shared.shouldTryPreferred(scope: routeScope)
            } else {
                tryPreferred = false
            }
            var preferredFailureWorthRemembering = false
            // R3: Apple's newer ent/download transport uses an account-bound KBSync
            // blob. Preserve R20 fallback; cool down R3 only after repeated
            // transport failures followed by successful legacy downloads.
            var preferredResponse: [String: Any]?
            if tryPreferred {
                var reachedPreferredTransport = false
                do {
                    let preferredVersion: String
                    if let version {
                        preferredVersion = version
                    } else {
                        guard let region else { throw StoreDownloadError.catalogUnavailable }
                        let metadata = try await catalogVersion(session: session, appID: app.id,
                                                                region: region, platform: platform, trace: trace)
                        guard metadata.bundleID == nil || metadata.bundleID == app.bundleID else {
                            throw StoreDownloadError.catalogUnavailable
                        }
                        preferredVersion = metadata.externalVersionID
                    }
                    reachedPreferredTransport = true
                    preferredResponse = try await fetchPreferred(session: session, account: &account,
                                                                  appID: app.id, bundleID: app.bundleID,
                                                                  version: preferredVersion, trace: trace)
                    effectiveVersion = preferredVersion
                } catch {
                    try Task.checkCancellation()
                    if modernHistoryOnly { throw error }
                    preferredFailureWorthRemembering = reachedPreferredTransport && isPreferredTransportFailure(error)
                    logger.info("Store download [\(trace)]: preferred transport unavailable, trying legacy transport; \(StoreDiagnostics.errorSummary(error))")
                }
            } else if operation == "download" {
                logger.info("Store download [\(trace)]: preferred route on cooldown; trying verified legacy transport")
            }
            let response: [String: Any]
            if let preferredResponse {
                response = preferredResponse
            } else {
                guard !modernHistoryOnly else { throw StoreDownloadError.empty }
                response = try await StoreDownloadProtocol.fetchWithFallback(version: version) { endpoint, requestedVersion in
                    effectiveVersion = requestedVersion
                    return try await fetch(session: session, endpoint: endpoint, account: &account,
                                           appID: app.id, version: requestedVersion, trace: trace)
                } resolveVersion: {
                    // An unpinned redownload can return a tvOS build for an iOS app.
                    guard let region else { throw StoreDownloadError.catalogUnavailable }
                    let metadata: StoreDownloadProtocol.CatalogVersion
                    do {
                        metadata = try await catalogVersion(session: session, appID: app.id, region: region,
                                                            platform: platform, trace: trace)
                    } catch {
                        try Task.checkCancellation()
                        throw StoreDownloadError.catalogUnavailable
                    }
                    guard !metadata.externalVersionID.isEmpty,
                          metadata.bundleID == nil || metadata.bundleID == app.bundleID
                    else { throw StoreDownloadError.catalogUnavailable }
                    logger.info("Store download [\(trace)]: catalog version=\(metadata.externalVersionID)")
                    return metadata.externalVersionID
                } onFallback: { reason in
                    logger.info("Store download [\(trace)]: trying \(reason.hasPrefix("redownload-") ? "update" : "redownload"), reason=\(reason)")
                }
            }
            // Surface license-missing to the one-tap download coordinator.
            if StoreDownloadProtocol.failureCode(response) == "9610" {
                throw ApplePackageError.licenseRequired
            }
            let item = try StoreDownloadProtocol.packageItem(response, bundleID: app.bundleID, version: effectiveVersion)
            let result = try await parse(item)
            if operation == "download" {
                if preferredResponse != nil {
                    await DownloadRouteAdvisor.shared.preferredSucceeded(scope: routeScope)
                } else if preferredFailureWorthRemembering {
                    await DownloadRouteAdvisor.shared.fallbackSucceededAfterPreferredFailure(scope: routeScope)
                }
            }
            logger.info("Store download [\(trace)]: product metadata ready")
            return result
        } catch {
            // localizedDescription and NSError.userInfo can contain Apple messages
            // or a credential-bearing URL. Log only the error type and numeric code.
            logger.error("Store download [\(trace)]: failed, \(StoreDiagnostics.errorSummary(error))")
            throw error
        }
    }

    /// A rejected license, Apple ID challenge, or cancelled task is not an
    /// indication that the preferred network transport is unhealthy.
    private static func isPreferredTransportFailure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? StoreDownloadError {
            switch failure {
            case .invalidPackage, .invalidRedirect, .empty:
                return true
            case let .response(status), let .emptyResponse(status):
                return status == 0 || status == 404 || status >= 500
            case .catalogUnavailable, .actionRequired, .noVersions, .rejected:
                return false
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code != NSURLErrorCancelled
    }

    private static func catalogVersion(session: URLSession, appID: Int64, region: String, platform: EntityType, trace: String) async throws -> StoreDownloadProtocol.CatalogVersion {
        var url = URLComponents(string: "https://uclient-api.itunes.apple.com/WebObjects/MZStorePlatform.woa/wa/lookup")!
        url.queryItems = [
            URLQueryItem(name: "version", value: "2"), URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "p", value: "mdm-lockup"), URLQueryItem(name: "caller", value: "MDM"),
            URLQueryItem(name: "platform", value: platform == .appleTV ? "atv9" : "enterprisestore"),
            URLQueryItem(name: "cc", value: region.lowercased()), URLQueryItem(name: "l", value: "en"),
        ]
        var request = URLRequest(url: url.url!)
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        // No credentials and no automatic redirects. Foundation verifies TLS in
        // Debug too (ApplePackage 1.2.7 disables verification in its Debug client).
        let (data, response) = try await dataWithRetry(session: session, request: request, trace: trace)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.info("Store download [\(trace)]: catalog HTTP=\(status) bytes=\(data.count)")
        guard status == 200 else { throw StoreDownloadError.catalogUnavailable }
        return try StoreDownloadProtocol.catalogVersion(data, appID: appID)
    }

    private static func fetch(session: URLSession, endpoint: StoreDownloadProtocol.Endpoint,
                              account: inout Account, appID: Int64, version: String?, trace: String) async throws -> [String: Any]
    {
        var components = URLComponents()
        components.scheme = "https"
        components.host = endpoint == .volumeStore ? Configuration.storeAPIHost(pod: account.pod) : "downloaddispatch.itunes.apple.com"
        components.path = endpoint.path
        if endpoint == .update {
            let bag = try? await Bag.fetchBag()
            guard let update = bag?.updateEndpoint,
                  let advertised = URLComponents(url: update, resolvingAgainstBaseURL: false)
            else { throw StoreDownloadError.emptyResponse(500) }
            components = advertised
        }
        components.queryItems = [URLQueryItem(name: "guid", value: Configuration.deviceIdentifier)]
        guard var url = components.url else { throw StoreDownloadError.invalidRedirect }
        let body = try PropertyListSerialization.data(
            fromPropertyList: StoreDownloadProtocol.payload(endpoint: endpoint, appID: appID,
                                                            guid: Configuration.deviceIdentifier, version: version),
            format: .xml, options: 0,
        )
        for redirect in 0 ... 3 {
            try Task.checkCancellation()
            url = try StoreDownloadProtocol.validatedURL(url)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
            request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ", "), forHTTPHeaderField: "Accept-Language")
            request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
            request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
            for (name, value) in account.cookie.buildCookieHeader(url) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            logger.info("Store download [\(trace)]: endpoint=\(endpoint.rawValue) hop=\(redirect) sessionCookie=\(request.value(forHTTPHeaderField: "Cookie") != nil)")
            let (data, response) = try await dataWithRetry(session: session, request: request, trace: trace)
            guard let response = response as? HTTPURLResponse else { throw StoreDownloadError.response(0) }
            mergeCookies(response: response, url: url, account: &account)
            logger.info("Store download [\(trace)]: endpoint=\(endpoint.rawValue) HTTP=\(response.statusCode) bytes=\(data.count)")
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard redirect < 3, let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL
                else { throw StoreDownloadError.invalidRedirect }
                url = try StoreDownloadProtocol.validatedURL(next)
                continue
            }
            let plist = StoreProtocol.plist(data)
            if let plist {
                logger.info("Store download [\(trace)]: \(StoreDownloadProtocol.summary(plist))")
            }
            guard response.statusCode == 200, let plist else {
                if data.isEmpty {
                    throw StoreDownloadError.emptyResponse(response.statusCode)
                }
                throw StoreDownloadError.response(response.statusCode)
            }
            return plist
        }
        throw StoreDownloadError.invalidRedirect
    }

    /// Preferred R3 request. No redirects are followed because X-Token must never
    /// be sent to a different destination. Only the fixed Apple endpoint is used.
    private static func fetchPreferred(session: URLSession, account: inout Account, appID: Int64,
                                       bundleID: String, version: String, trace: String) async throws -> [String: Any]
    {
        let guid = Configuration.deviceIdentifier
        let dsid = account.directoryServicesIdentifier
        guard !version.isEmpty, guid.count == 12,
              let suffix = UInt32(guid.suffix(8), radix: 16)
        else { throw StoreDownloadError.invalidPackage }
        // KBSync may fail before any request reaches Apple's download server.
        // Log a fixed stage code so failures can be diagnosed without leaking
        // credentials, device identifiers, the blob, or a signed package URL.
        logger.info("Store download [\(trace)]: kbsync preparation starting")
        // Generate only after an explicit GET request, keeping the native
        // preparation detached from the UI and on a user-initiated priority.
        // Never preload the expensive emulator while browsing/searching.
        let generation = await Task.detached(priority: .userInitiated) {
            R3KBSync.generate(guid: guid, directoryServicesIdentifier: dsid)
        }.value
        logger.info("Store download [\(trace)]: kbsync status=\(generation.status)")
        guard let blob = generation.blob else { throw StoreDownloadError.invalidPackage }

        var serial = Data([0x54, 0xc8, 0xb0, 0xa9, 0x88])
        serial.append(contentsOf: [
            UInt8((suffix >> 24) & 0xff), UInt8((suffix >> 16) & 0xff),
            UInt8((suffix >> 8) & 0xff), UInt8(suffix & 0xff),
        ])
        var components = URLComponents()
        components.scheme = "https"
        components.host = "downloaddispatch.itunes.apple.com"
        components.path = "/WebObjects/DownloadDispatch.woa/wa/ent/download"
        guard let url = components.url, url.scheme == "https",
              url.host == "downloaddispatch.itunes.apple.com"
        else { throw StoreDownloadError.invalidRedirect }
        let payload: [String: Any] = [
            "creditDisplay": "", "guid": guid, "kbsync": blob,
            "salableAdamId": String(appID), "serialNumber": serial.base64EncodedString(),
            "externalVersionId": version,
        ]
        let body = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Configurator/2.18 (Macintosh; OS X 15.3.2; 24D81) AppleWebKit/0620.2.4.11.6",
                         forHTTPHeaderField: "User-Agent")
        request.setValue(account.store, forHTTPHeaderField: "X-Apple-Store-Front")
        request.setValue(account.passwordToken, forHTTPHeaderField: "X-Token")
        request.setValue(dsid, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(dsid, forHTTPHeaderField: "X-Dsid")
        for (name, value) in account.cookie.buildCookieHeader(url) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        logger.info("Store download [\(trace)]: endpoint=ent/download request starting")
        let (data, response) = try await dataWithRetry(session: session, request: request, trace: trace)
        guard let response = response as? HTTPURLResponse else { throw StoreDownloadError.response(0) }
        logger.info("Store download [\(trace)]: endpoint=ent/download HTTP=\(response.statusCode) bytes=\(data.count)")
        // No re-POST on redirects, ever. Responses are validated before use.
        guard response.statusCode == 200, let plist = StoreProtocol.plist(data)
        else { throw StoreDownloadError.response(response.statusCode) }
        logger.info("Store download [\(trace)]: \(StoreDownloadProtocol.summary(plist))")
        let item = try StoreDownloadProtocol.packageItem(plist, bundleID: bundleID, version: version)
        guard let urlText = item["URL"] as? String, !urlText.isEmpty,
              let signatures = item["sinfs"] as? [[String: Any]], !signatures.isEmpty
        else { throw StoreDownloadError.invalidPackage }
        mergeCookies(response: response, url: url, account: &account)
        return plist
    }

    private static func mergeCookies(response: HTTPURLResponse, url: URL, account: inout Account) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let name = field.key as? String, let value = field.value as? String {
                result[name] = value
            }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            let domain = StoreProtocol.storeCookieDomain(cookie.domain)
            account.cookie.removeAll { $0.name == cookie.name && $0.path == cookie.path && StoreProtocol.storeCookieDomain($0.domain) == domain }
            if let expiry = cookie.expiresDate, expiry <= Date() {
                continue
            }
            account.cookie.append(Cookie(name: cookie.name, value: cookie.value, path: cookie.path, domain: domain,
                                         expiresAt: cookie.expiresDate?.timeIntervalSince1970, httpOnly: cookie.isHTTPOnly, secure: cookie.isSecure))
        }
    }

    /// A one-time retry hides short Apple CDN/dispatch failures without
    /// repeating purchases or account auth. Signed URLs and tokens are never
    /// written to diagnostics, and cancellation exits immediately.
    private static func dataWithRetry(session: URLSession, request: URLRequest,
                                      trace: String) async throws -> (Data, URLResponse)
    {
        for attempt in 0 ..< 2 {
            try Task.checkCancellation()
            do {
                let result = try await session.data(for: request)
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                if attempt == 0, StoreDownloadProtocol.isTransientHTTPStatus(status) {
                    logger.info("Store download [\(trace)]: temporary HTTP=\(status), retrying metadata request once")
                    try await Task.sleep(for: .milliseconds(400))
                    continue
                }
                return result
            } catch {
                try Task.checkCancellation()
                guard attempt == 0, StoreDownloadProtocol.isTransientNetworkError(error) else { throw error }
                logger.info("Store download [\(trace)]: temporary network error, retrying metadata request once")
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw StoreDownloadError.response(0)
    }

    /// ApplePackage's DownloadOutput format, also consumed by SignatureInjector.
    private static func output(item: [String: Any], email: String, bundleID: String) async throws -> DownloadOutput {
        guard let url = item["URL"] as? String, let asset = URL(string: url),
              ["https", "http"].contains(asset.scheme), asset.host != nil,
              var metadata = item["metadata"] as? [String: Any],
              let signatures = item["sinfs"] as? [[String: Any]], !signatures.isEmpty
        else { throw StoreDownloadError.invalidPackage }
        let sinfs = try signatures.map { signature -> Sinf in
            guard let id = signature["id"] as? Int64, let data = signature["sinf"] as? Data else {
                throw StoreDownloadError.invalidPackage
            }
            return Sinf(id: id, sinf: data)
        }
        var version = metadata["bundleShortVersionString"] as? String ?? ""
        var build = metadata["bundleVersion"] as? String ?? ""
        if version.isEmpty || build.isEmpty {
            guard asset.scheme == "https" else { throw StoreDownloadError.invalidPackage }
            let verified = try await RemoteIPAInfoPlist.read(url: asset, bundleID: bundleID)
            version = verified.version
            build = verified.build
            metadata["bundleShortVersionString"] = version
            metadata["bundleVersion"] = build
        }
        metadata["apple-id"] = email
        metadata["userName"] = email
        return try DownloadOutput(downloadURL: url, sinfs: sinfs, bundleShortVersionString: version,
                                  bundleVersion: build, iTunesMetadata: PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0))
    }
}
