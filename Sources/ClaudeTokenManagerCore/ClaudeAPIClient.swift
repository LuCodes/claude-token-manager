import Foundation
import CryptoKit

public final class ClaudeAPIClient: @unchecked Sendable {
    public static let shared = ClaudeAPIClient()

    public struct Endpoints {
        public static let baseURL = "https://claude.ai/api"
        public static func usageReport(orgId: String) -> String {
            return "\(baseURL)/organizations/\(orgId)/usage"
        }
    }

    private let session: URLSession
    private let pinDelegate = PinnedURLSessionDelegate()
    private let decoder: JSONDecoder

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            self.session = URLSession(
                configuration: config,
                delegate: pinDelegate,
                delegateQueue: nil
            )
        }
        self.decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(str)"
            )
        }
    }

    public func fetchUsageReport(
        organizationId: String,
        sessionKey: SessionKey
    ) async throws -> RawUsageReport {
        guard !sessionKey.isEmpty else {
            throw DataSourceError.authenticationRequired
        }
        guard let url = URL(string: Endpoints.usageReport(orgId: organizationId)) else {
            throw DataSourceError.apiChanged(details: "invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            forHTTPHeaderField: "user-agent"
        )
        request.setValue("sessionKey=\(sessionKey.unsafeRawValue)",
                         forHTTPHeaderField: "cookie")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DataSourceError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DataSourceError.networkError(
                underlying: NSError(domain: "ClaudeAPIClient", code: -1)
            )
        }

        switch http.statusCode {
        case 200: break
        case 401, 403: throw DataSourceError.authenticationExpired
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw DataSourceError.rateLimited(retryAfter: retry)
        case 500...599:
            throw DataSourceError.networkError(
                underlying: NSError(domain: "ClaudeAPIClient", code: http.statusCode)
            )
        default:
            throw DataSourceError.apiChanged(
                details: "unexpected HTTP status \(http.statusCode)"
            )
        }

        do {
            return try decoder.decode(RawUsageReport.self, from: data)
        } catch {
            throw DataSourceError.parseError(details: "failed to decode usage JSON")
        }
    }
}

// MARK: - Response types

public struct RawUsageReport: Codable, Sendable {
    public let fiveHour: Pool?
    public let sevenDay: Pool?
    public let sevenDayOauthApps: Pool?
    public let sevenDayOpus: Pool?
    public let sevenDaySonnet: Pool?
    public let sevenDayCowork: Pool?
    public let sevenDayOmelette: Pool?
    public let iguanaNecktie: Pool?
    public let omelettePromotional: Pool?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayOmelette = "seven_day_omelette"
        case iguanaNecktie = "iguana_necktie"
        case omelettePromotional = "omelette_promotional"
        case extraUsage = "extra_usage"
    }

    public struct Pool: Codable, Sendable {
        public let utilization: Double
        public let resetsAt: Date
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool
        public let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }
}

// MARK: - Certificate pinning

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    /// SHA-256 hashes of the public keys we trust for claude.ai.
    /// IMPORTANT: populate with output of scripts/extract-spki-hash.sh before release.
    /// When empty, falls back to system trust (pinning disabled).
    private let pinnedSPKIHashes: Set<String> = [
        // TODO: Lucas must run scripts/extract-spki-hash.sh and paste hashes here
    ]

    private let hostToPin = "claude.ai"

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.hasSuffix(hostToPin),
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = chain.first,
              let publicKey = SecCertificateCopyKey(leafCert),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let hash = SHA256.hash(data: publicKeyData)
        let hashBase64 = Data(hash).base64EncodedString()

        if pinnedSPKIHashes.isEmpty {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        if pinnedSPKIHashes.contains(hashBase64) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
